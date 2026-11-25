// Build and install with install-clipboard-tools.sh.
// Install lsc as a symlink to pf.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/stat.h>

@interface ClipboardEntry : NSObject
@property (nonatomic, strong) NSURL *source;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *name;
@end

@implementation ClipboardEntry
@end

static int fail(NSString *message) {
    fprintf(stderr, "%s: %s\n", getprogname(), message.UTF8String);
    return 1;
}

static OSStatus readFileURLs(PasteboardRef clipboard, NSMutableDictionary<NSNumber *, NSURL *> *urls) {
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
        if (url.isFileURL && url.path.isAbsolutePath &&
            (!url.host.length || [url.host.lowercaseString isEqualToString:@"localhost"])) {
            urls[@(index - 1)] = url;
        }
    }
    return noErr;
}

static NSDictionary<NSNumber *, NSURL *> *clipboardFileURLs(void) {
    PasteboardRef clipboard;
    OSStatus status = PasteboardCreate(kPasteboardClipboard, &clipboard);
    NSMutableDictionary<NSNumber *, NSURL *> *urls = [NSMutableDictionary dictionary];
    if (status == noErr) {
        status = readFileURLs(clipboard, urls);
        CFRelease(clipboard);
    }
    if (status != noErr) {
        fail([NSString stringWithFormat:@"could not read clipboard files (macOS error %d)",
              (int)status]);
        return nil;
    }

    return urls;
}

static ClipboardEntry *fileEntry(NSURL *source) {
    ClipboardEntry *entry = [ClipboardEntry new];
    entry.source = source;
    entry.name = source.lastPathComponent;
    return entry;
}

static UTType *typeForFlavor(NSString *flavor) {
    return [UTType typeWithIdentifier:flavor] ?:
        ([flavor containsString:@"/"] ? [UTType typeWithMIMEType:flavor] : nil);
}

static NSString *filenameExtension(UTType *type) {
    return type.preferredFilenameExtension ?:
        ([type conformsToType:UTTypePlainText] ? UTTypePlainText.preferredFilenameExtension : nil);
}

static ClipboardEntry *dataEntry(NSPasteboardItem *item, UTType *requestedType) {
    NSArray<NSPasteboardType> *flavors = item.types;
    NSMutableOrderedSet<NSPasteboardType> *candidates = [NSMutableOrderedSet orderedSet];
    if (requestedType) {
        for (NSPasteboardType flavor in flavors) {
            if ([typeForFlavor(flavor) conformsToType:requestedType]) [candidates addObject:flavor];
        }
    }
    for (NSPasteboardType flavor in flavors) {
        if (filenameExtension(typeForFlavor(flavor)).length) [candidates addObject:flavor];
    }
    [candidates addObjectsFromArray:flavors];

    ClipboardEntry *entry = [ClipboardEntry new];
    entry.type = candidates.firstObject ?: UTTypeItem.identifier;
    for (NSPasteboardType flavor in candidates) {
        NSData *data = [item dataForType:flavor];
        if (!data) continue;
        entry.type = flavor;
        entry.data = data;
        if ([typeForFlavor(flavor) conformsToType:UTTypePlainText]) {
            entry.text = [item stringForType:NSPasteboardTypeString] ?: [item stringForType:flavor];
        }
        break;
    }
    NSString *extension = filenameExtension(typeForFlavor(entry.type));
    if (!extension.length || ![extension isEqualToString:extension.lastPathComponent]) extension = @"bin";
    entry.name = [@"clipboard" stringByAppendingPathExtension:extension];
    return entry;
}

static NSArray<ClipboardEntry *> *clipboardEntries(NSPasteboard *board, UTType *requestedType) {
    NSDictionary<NSNumber *, NSURL *> *urls = clipboardFileURLs();
    if (!urls) return nil;

    NSMutableArray<ClipboardEntry *> *entries = [NSMutableArray array];
    NSArray<NSPasteboardItem *> *items = board.pasteboardItems;
    // Some apps publish a full filename list alongside an incomplete set of file URLs.
    id paths = [board propertyListForType:@"NSFilenamesPboardType"];
    BOOL useFilenameList = [paths isKindOfClass:NSArray.class] && [paths count] > urls.count;
    if (useFilenameList) {
        for (id path in paths) {
            if (![path isKindOfClass:NSString.class] || ![path isAbsolutePath]) {
                fail(@"clipboard contains an invalid file path");
                return nil;
            }
            [entries addObject:fileEntry([NSURL fileURLWithPath:path])];
        }
    }

    NSUInteger count = items.count;
    for (NSNumber *index in urls) count = MAX(count, index.unsignedIntegerValue + 1);
    for (NSUInteger index = 0; index < count; ++index) {
        NSURL *url = urls[@(index)];
        if (url) {
            if (!useFilenameList) [entries addObject:fileEntry(url)];
        } else if (index < items.count) {
            NSPasteboardItem *item = items[index];
            if (useFilenameList && ([item.types containsObject:NSPasteboardTypeFileURL] ||
                                   [item.types containsObject:@"NSFilenamesPboardType"])) continue;
            [entries addObject:dataEntry(item, count == 1 && !useFilenameList ? requestedType : nil)];
        }
    }
    return entries;
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

static int paste(NSArray<ClipboardEntry *> *entries, NSString *path) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *target = [NSURL fileURLWithPath:path];
    BOOL isDirectory = NO;
    BOOL exists = [files fileExistsAtPath:target.path isDirectory:&isDirectory];
    BOOL useDirectory = isDirectory || entries.count > 1 || [path hasSuffix:@"/"];
    if (useDirectory && exists && !isDirectory) {
        return fail([NSString stringWithFormat:@"destination is not a directory: %@", target.path]);
    }

    NSURL *directory = useDirectory ? target : target.URLByDeletingLastPathComponent;
    NSString *destinationName = useDirectory ? nil : target.lastPathComponent;
    NSString *targetDirectory = directory.URLByResolvingSymlinksInPath.path;
    for (ClipboardEntry *entry in entries) {
        NSURL *source = entry.source;
        if (!source) {
            if (!entry.data) return fail([NSString stringWithFormat:@"clipboard data is unavailable: %@", entry.type]);
            continue;
        }
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
    if (!scratch) return fail([NSString stringWithFormat:@"%@: %s", directory.path, strerror(scratchError)]);

    @try {
        NSMutableArray<NSURL *> *stagedFiles = [NSMutableArray array];
        for (ClipboardEntry *entry in entries) {
            NSString *index = [NSString stringWithFormat:@"%lu", (unsigned long)stagedFiles.count];
            NSURL *staged = [scratch URLByAppendingPathComponent:index];
            BOOL written = entry.source ? [files copyItemAtURL:entry.source toURL:staged error:&error]
                : [entry.data writeToURL:staged options:0 error:&error];
            if (!written) return fail(error.localizedDescription);
            [stagedFiles addObject:staged];
        }
        for (NSUInteger index = 0; index < stagedFiles.count; ++index) {
            NSURL *destination = publishFile(stagedFiles[index], directory, destinationName ?: entries[index].name);
            if (!destination) return 1;
            puts(destination.fileSystemRepresentation);
        }
        return 0;
    } @finally {
        [files removeItemAtURL:scratch error:nil];
    }
}

static int listDiskPaths(NSArray<NSString *> *paths) {
    if (!paths.count) return 0;
    if (fflush(stdout) == EOF) return fail(@"could not print clipboard information");

    NSTask *ls = [NSTask new];
    ls.executableURL = [NSURL fileURLWithPath:@"/bin/ls"];
    // List the copied paths themselves in clipboard order, including directories and dotfiles.
    ls.arguments = [@[@"-ladf", @"--"] arrayByAddingObjectsFromArray:paths];
    NSError *error;
    if (![ls launchAndReturnError:&error]) return fail(error.localizedDescription);
    [ls waitUntilExit];
    return ls.terminationStatus;
}

static int listClipboard(NSArray<ClipboardEntry *> *entries) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSUInteger index = 0; index < entries.count; ++index) {
        ClipboardEntry *entry = entries[index];
        if (entry.source) {
            [paths addObject:entry.source.path];
            continue;
        }

        int status = listDiskPaths(paths);
        if (status) return status;
        [paths removeAllObjects];
        if (entry.text) {
            NSData *bytes = [entry.text dataUsingEncoding:NSUTF8StringEncoding];
            if (!bytes || (bytes.length && fwrite(bytes.bytes, 1, bytes.length, stdout) != bytes.length)) {
                return fail(@"could not print clipboard text");
            }
            if (index + 1 < entries.count && ![entry.text hasSuffix:@"\n"]) putchar('\n');
            continue;
        }

        int printed = entry.data ? printf("%lu %s\n", (unsigned long)entry.data.length, entry.name.UTF8String)
            : puts(entry.name.UTF8String);
        if (printed < 0) {
            return fail(@"could not print clipboard information");
        }
    }
    if (fflush(stdout) == EOF) return fail(@"could not print clipboard contents");
    return listDiskPaths(paths);
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

        UTType *requestedType = nil;
        if (!listing && path.pathExtension.length && ![path hasSuffix:@"/"]) {
            BOOL directory = NO;
            [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory];
            if (!directory) requestedType = [UTType typeWithFilenameExtension:path.pathExtension];
        }
        NSPasteboard *board = NSPasteboard.generalPasteboard;
        NSInteger change = board.changeCount;
        NSArray<ClipboardEntry *> *entries = clipboardEntries(board, requestedType);
        if (!entries) return 1;
        if (board.changeCount != change) return fail(@"clipboard changed while reading it");
        if (!entries.count) return fail(@"clipboard is empty");
        return listing ? listClipboard(entries) : paste(entries, path);
    }
}
