// Build: clang -fobjc-arc -framework AppKit -framework ApplicationServices pf.m -o pf
// Install lsc as a symlink to pf.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <sys/stat.h>

static int fail(NSString *message) {
    fprintf(stderr, "%s: %s\n", getprogname(), message.UTF8String);
    return 1;
}

static OSStatus readFileURLs(PasteboardRef clipboard, NSMutableArray<NSURL *> *urls) {
    PasteboardSynchronize(clipboard);
    ItemCount count;
    OSStatus status = PasteboardGetItemCount(clipboard, &count);
    if (status != noErr) return status;

    for (ItemCount index = 1; index <= count; ++index) {
        PasteboardItemID item;
        status = PasteboardGetItemIdentifier(clipboard, index, &item);
        if (status != noErr) return status;

        CFDataRef bytes;
        status = PasteboardCopyItemFlavorData(clipboard, item, CFSTR("public.file-url"), &bytes);
        if (status == badPasteboardFlavorErr) continue;
        if (status != noErr) return status;

        // Read the URL representation without asking AppKit for a sandbox extension.
        NSString *string = [[NSString alloc] initWithData:CFBridgingRelease(bytes)
                                                 encoding:NSUTF8StringEncoding];
        NSURL *url = string ? [NSURL URLWithString:string] : nil;
        if (!url.isFileURL || !url.path.isAbsolutePath ||
            (url.host.length && ![url.host.lowercaseString isEqualToString:@"localhost"])) {
            return badPasteboardFlavorErr;
        }
        [urls addObject:url];
    }
    return noErr;
}

static NSArray<NSURL *> *clipboardFiles(NSPasteboard *board) {
    PasteboardRef clipboard;
    OSStatus status = PasteboardCreate(kPasteboardClipboard, &clipboard);
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    if (status == noErr) {
        status = readFileURLs(clipboard, urls);
        CFRelease(clipboard);
    }
    if (status != noErr) {
        fail([NSString stringWithFormat:@"could not read clipboard files (macOS error %d)",
              (int)status]);
        return nil;
    }

    // Some apps publish the full list of paths separately from the individual URLs.
    id paths = [board propertyListForType:@"NSFilenamesPboardType"];
    if ([paths isKindOfClass:NSArray.class] && [paths count] > urls.count) {
        NSMutableArray<NSURL *> *complete = [NSMutableArray array];
        for (id path in paths) {
            if (![path isKindOfClass:NSString.class] || ![path isAbsolutePath]) {
                fail(@"clipboard contains an invalid file path");
                return nil;
            }
            [complete addObject:[NSURL fileURLWithPath:path]];
        }
        return complete;
    }
    return urls;
}

static NSString *askFilename(void) {
    fputs("Имя файла: ", stderr);
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length = getline(&line, &capacity, stdin);
    if (length > 0 && line[length - 1] == '\n') --length;
    NSString *name = length > 0 && !memchr(line, '\0', (size_t)length)
        ? [[NSString alloc] initWithBytes:line length:(NSUInteger)length encoding:NSUTF8StringEncoding]
        : nil;
    free(line);
    if (!name.length || [name containsString:@"/"] || [name isEqualToString:@"."] ||
        [name isEqualToString:@".."]) {
        fail(@"provide a file name without a directory");
        return nil;
    }
    return name;
}

static NSURL *publishFile(NSURL *staged, NSURL *directory, NSString *name) {
    NSString *extension = name.pathExtension;
    NSString *stem = name.stringByDeletingPathExtension;
    NSURL *destination = [directory URLByAppendingPathComponent:name];
    for (NSUInteger suffix = 2; ; ++suffix) {
        if (renamex_np(staged.fileSystemRepresentation, destination.fileSystemRepresentation,
                       RENAME_EXCL) == 0) return destination;
        if (errno != EEXIST) {
            int code = errno;
            fail([NSString stringWithFormat:@"%@: %s", destination.path, strerror(code)]);
            return nil;
        }
        NSString *next = [NSString stringWithFormat:@"%@-%lu", stem, (unsigned long)suffix];
        if (extension.length) next = [next stringByAppendingPathExtension:extension];
        destination = [directory URLByAppendingPathComponent:next];
    }
}

static int paste(NSArray<NSURL *> *sources, NSString *text, NSString *path) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *target = [NSURL fileURLWithPath:path];
    BOOL isDirectory = NO;
    BOOL exists = [files fileExistsAtPath:target.path isDirectory:&isDirectory];
    BOOL useDirectory = isDirectory || sources.count > 1 || [path hasSuffix:@"/"];
    if (useDirectory && exists && !isDirectory) {
        return fail([NSString stringWithFormat:@"destination is not a directory: %@", target.path]);
    }

    NSURL *directory = useDirectory ? target : target.URLByDeletingLastPathComponent;
    NSString *destinationName = useDirectory ? nil : target.lastPathComponent;
    if (text && !destinationName) {
        destinationName = askFilename();
        if (!destinationName) return 1;
    }

    NSString *targetDirectory = directory.URLByResolvingSymlinksInPath.path;
    for (NSURL *source in sources) {
        struct stat info;
        if (lstat(source.fileSystemRepresentation, &info) != 0) {
            int code = errno;
            return fail([NSString stringWithFormat:@"%@: %s", source.path, strerror(code)]);
        }
        if (S_ISDIR(info.st_mode)) {
            NSString *sourceDirectory = source.URLByResolvingSymlinksInPath.path;
            NSString *prefix = [sourceDirectory hasSuffix:@"/"] ? sourceDirectory
                : [sourceDirectory stringByAppendingString:@"/"];
            if ([targetDirectory isEqualToString:sourceDirectory] || [targetDirectory hasPrefix:prefix]) {
                return fail([NSString stringWithFormat:@"cannot copy a directory into itself: %@", source.path]);
            }
        }
    }

    NSError *error = nil;
    if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES
                          attributes:nil error:&error]) return fail(error.localizedDescription);

    // Stage the contents on the destination volume before publishing any final names.
    NSURL *scratchTemplate = [directory URLByAppendingPathComponent:@".pf-XXXXXXXX"];
    char *scratchPath = strdup(scratchTemplate.fileSystemRepresentation);
    if (!scratchPath) return fail(@"could not allocate a temporary path");
    NSURL *scratch = nil;
    int scratchError = 0;
    if (mkdtemp(scratchPath)) {
        scratch = [NSURL fileURLWithFileSystemRepresentation:scratchPath isDirectory:YES relativeToURL:nil];
    } else {
        scratchError = errno;
    }
    free(scratchPath);
    if (!scratch) return fail([NSString stringWithFormat:@"%@ : %s", directory.path, strerror(scratchError)]);

    @try {
        NSMutableArray<NSURL *> *stagedFiles = [NSMutableArray array];
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        if (text) {
            NSURL *staged = [scratch URLByAppendingPathComponent:@"text"];
            if (![text writeToURL:staged atomically:NO encoding:NSUTF8StringEncoding error:&error]) {
                return fail(error.localizedDescription);
            }
            [stagedFiles addObject:staged];
            [names addObject:destinationName];
        }
        for (NSURL *source in sources) {
            NSString *index = [NSString stringWithFormat:@"%lu", (unsigned long)stagedFiles.count];
            NSURL *staged = [scratch URLByAppendingPathComponent:index];
            if (![files copyItemAtURL:source toURL:staged error:&error]) return fail(error.localizedDescription);
            [stagedFiles addObject:staged];
            [names addObject:destinationName ?: source.lastPathComponent];
        }
        for (NSUInteger index = 0; index < stagedFiles.count; ++index) {
            NSURL *destination = publishFile(stagedFiles[index], directory, names[index]);
            if (!destination) return 1;
            puts(destination.fileSystemRepresentation);
        }
        return 0;
    } @finally {
        [files removeItemAtURL:scratch error:nil];
    }
}

static int listClipboard(NSArray<NSURL *> *sources, NSString *text) {
    if (text) {
        NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
        if (!bytes || (bytes.length && fwrite(bytes.bytes, 1, bytes.length, stdout) != bytes.length)) {
            return fail(@"could not print clipboard text");
        }
    } else {
        for (NSURL *source in sources) {
            if (puts(source.path.UTF8String) == EOF) return fail(@"could not print clipboard paths");
        }
    }
    return fflush(stdout) == 0 ? 0 : fail(@"could not print clipboard contents");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL listing = strcmp(getprogname(), "lsc") == 0;
        int pathIndex = argc > 1 && strcmp(argv[1], "--") == 0 ? 2 : 1;
        if (argc > (listing ? 1 : pathIndex + 1)) {
            fputs(listing ? "Usage: lsc\n" : "Usage: pf [--] [PATH]\n", stderr);
            return 2;
        }
        NSString *path = argc > pathIndex
            ? [NSFileManager.defaultManager stringWithFileSystemRepresentation:argv[pathIndex]
                                                                       length:strlen(argv[pathIndex])]
            : @".";
        if (!path.length) return fail(@"destination path is empty");

        NSPasteboard *board = NSPasteboard.generalPasteboard;
        NSInteger change = board.changeCount;
        NSArray<NSURL *> *sources = clipboardFiles(board);
        if (!sources) return 1;
        NSString *text = sources.count ? nil : [board stringForType:NSPasteboardTypeString];
        if (board.changeCount != change) return fail(@"clipboard changed while reading it");
        if (!sources.count && !text) return fail(@"clipboard has no files or plain text");
        return listing ? listClipboard(sources, text) : paste(sources, text, path);
    }
}
