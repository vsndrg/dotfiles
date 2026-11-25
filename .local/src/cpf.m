// Build with clang -fobjc-arc -framework AppKit -framework ApplicationServices.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static OSStatus confirmFileURLs(PasteboardRef clipboard, ItemCount expectedCount) {
    PasteboardSynchronize(clipboard);

    ItemCount count;
    OSStatus status = PasteboardGetItemCount(clipboard, &count);
    if (status != noErr) return status;
    if (count != expectedCount) return badPasteboardIndexErr;

    for (ItemCount index = 1; index <= count; ++index) {
        PasteboardItemID item;
        status = PasteboardGetItemIdentifier(clipboard, index, &item);
        if (status != noErr) return status;

        // Read the raw file URL so its data is published before this process exits.
        CFDataRef data;
        status = PasteboardCopyItemFlavorData(clipboard, item, CFSTR("public.file-url"), &data);
        if (status != noErr) return status;
        CFRelease(data);
    }
    return noErr;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fputs("Usage: cpf FILE [FILE ...]\n", stderr);
            return 2;
        }

        NSFileManager *files = NSFileManager.defaultManager;
        NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:argc - 1];
        for (int index = 1; index < argc; ++index) {
            NSString *path = [files stringWithFileSystemRepresentation:argv[index]
                                                               length:strlen(argv[index])];
            [urls addObject:[NSURL fileURLWithPath:path]];
        }

        NSPasteboard *board = NSPasteboard.generalPasteboard;
        [board clearContents];
        if (![board writeObjects:urls]) {
            fputs("cpf: could not write files to the clipboard\n", stderr);
            return 1;
        }

        PasteboardRef clipboard;
        OSStatus status = PasteboardCreate(kPasteboardClipboard, &clipboard);
        if (status == noErr) {
            status = confirmFileURLs(clipboard, (ItemCount)urls.count);
            CFRelease(clipboard);
        }
        if (status != noErr) {
            fprintf(stderr, "cpf: could not confirm all clipboard files (macOS error %d)\n",
                    (int)status);
            return 1;
        }
        return 0;
    }
}
