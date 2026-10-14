// Prints every symbol exported by the private UniversalControl.framework on this Mac.
// System frameworks live in the dyld shared cache, so this loads the image and walks
// its export trie in memory instead of reading a file on disk.

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const char *kPath = "/System/Library/PrivateFrameworks/UniversalControl.framework/Versions/A/UniversalControl";
static const uint8_t *trie;

static uint64_t uleb(const uint8_t **p) {
    uint64_t result = 0;
    int shift = 0;
    uint8_t byte;
    do {
        byte = *(*p)++;
        result |= (uint64_t)(byte & 0x7f) << shift;
        shift += 7;
    } while (byte & 0x80);
    return result;
}

static void walk(const uint8_t *node, char *name, int length) {
    const uint8_t *p = node;
    uint64_t terminal = uleb(&p);
    if (terminal) {
        name[length] = 0;
        puts(name);
    }
    p += terminal;
    uint8_t children = *p++;
    for (int i = 0; i < children; i++) {
        int end = length;
        while (*p) name[end++] = (char)*p++;
        p++;
        walk(trie + uleb(&p), name, end);
    }
}

int main(void) {
    if (!dlopen(kPath, RTLD_NOW)) {
        fprintf(stderr, "cannot load %s\n", kPath);
        return 1;
    }
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i), kPath) != 0) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command *command = (const void *)(header + 1);
        const struct segment_command_64 *linkedit = NULL;
        uint32_t offset = 0;
        for (uint32_t k = 0; k < header->ncmds; k++) {
            if (command->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)command)->segname, "__LINKEDIT"))
                linkedit = (const void *)command;
            if (command->cmd == LC_DYLD_EXPORTS_TRIE)
                offset = ((const struct linkedit_data_command *)command)->dataoff;
            if (command->cmd == LC_DYLD_INFO_ONLY)
                offset = ((const struct dyld_info_command *)command)->export_off;
            command = (const void *)((const char *)command + command->cmdsize);
        }
        if (!linkedit || !offset) return 1;
        trie = (const uint8_t *)(slide + linkedit->vmaddr - linkedit->fileoff + offset);
        char name[4096];
        walk(trie, name, 0);
        return 0;
    }
    return 1;
}
