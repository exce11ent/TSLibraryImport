//
//  TSLibraryImport.m
//  iPodLibraryAccess
//
//  Created by Art Gillespie on 7/9/10.
//  Copyright 2010 tapsquare, llc. All rights reserved.
//

#import "TSLibraryImport.h"

@interface TSLibraryImport()

+ (BOOL)validIpodLibraryURL:(NSURL*)url;
- (void)extractQuicktimeMovie:(NSURL*)movieURL toFile:(NSURL*)destURL;

@end


@implementation TSLibraryImport

+ (BOOL)validIpodLibraryURL:(NSURL*)url {
	NSString* IPOD_SCHEME = @"ipod-library";
	if (nil == url) return NO;
	if (nil == url.scheme) return NO;
	if ([url.scheme compare:IPOD_SCHEME] != NSOrderedSame) return NO;
	if ([url.pathExtension compare:@"mp3"] != NSOrderedSame &&
		[url.pathExtension compare:@"aif"] != NSOrderedSame &&
		[url.pathExtension compare:@"m4a"] != NSOrderedSame &&
		[url.pathExtension compare:@"wav"] != NSOrderedSame) {
		return NO;
	}
	return YES;
}

+ (NSString*)extensionForAssetURL:(NSURL*)assetURL {
	if (nil == assetURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil assetURL" userInfo:nil];
	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];
	return assetURL.pathExtension;
}

- (void)importAsset:(NSURL*)assetURL toURL:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock {
	//TODO: add completion handler to method

		if (nil == assetURL || nil == destURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil url" userInfo:nil];
	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];

	if ([[NSFileManager defaultManager] fileExistsAtPath:[destURL path]])
		 @throw [NSException exceptionWithName:@"TSFileExists" reason:[NSString stringWithFormat:@"File already exists at url: %@", destURL] userInfo:nil];
	
	NSDictionary * options = [[NSDictionary alloc] init];
	AVURLAsset* asset = [AVURLAsset URLAssetWithURL:assetURL options:options];	
	if (nil == asset) 
		@throw [NSException exceptionWithName:@"TSUnknownError" reason:[NSString stringWithFormat:@"Couldn't create AVURLAsset with url: %@", assetURL] userInfo:nil];
	
	export = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
	if (nil == export)
		@throw [NSException exceptionWithName:@"TSUnknownError" reason:@"Couldn't create AVAssetExportSession" userInfo:nil];
	
	//TODO: instead of putting this in the same directory as the dest file, we should probably stuff
	//this in tmp
	NSURL* tmpURL = [[destURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"mov"];
	[[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];
	export.outputURL = tmpURL;

	export.outputFileType = AVFileTypeQuickTimeMovie;
	[export exportAsynchronouslyWithCompletionHandler:^(void) {
		if (export.status == AVAssetExportSessionStatusFailed) {
			completionBlock(self);
		} else if (export.status == AVAssetExportSessionStatusCancelled) {
			completionBlock(self);
		} else {
			@try {
				[self extractQuicktimeMovie:tmpURL toFile:destURL];
			}
			@catch (NSException * e) {
				//TODO: Crap, since we're delegating status/error to our AVAssetExportSession instance, we have a problem here
				// Need to create our own status/error ivars
			}
			//clean up the tmp .mov file
			[[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];
			completionBlock(self);
		}
		[export release];
		export = nil;
	}];
}

- (void)extractQuicktimeMovie:(NSURL*)movieURL toFile:(NSURL*)destURL {
	FILE* src = fopen([[movieURL path] cStringUsingEncoding:NSUTF8StringEncoding], "r");
	if (NULL == src) {
		@throw [NSException exceptionWithName:@"TSUnknownException" reason:@"Couldn't open source file" userInfo:nil];
		return;
	}
	char atom_name[5];
	atom_name[4] = '\0';
	unsigned long atom_size = 0;
	while (true) {
		if (feof(src)) {
			break;
		}
		fread((void*)&atom_size, 4, 1, src);
		fread(atom_name, 4, 1, src);
		atom_size = ntohl(atom_size);
		if (strcmp("mdat", atom_name) == 0) {
			FILE* dst = fopen([[destURL path] cStringUsingEncoding:NSUTF8StringEncoding], "w");
			unsigned char buf[4];
			if (NULL == dst) {
				fclose(src);
				@throw [NSException exceptionWithName:@"TSUnknownException" reason:@"Couldn't open destination file" userInfo:nil];
			}
			for (uint32_t ii=0; ii<atom_size; ii+=4) {
				fread(buf, 4, 1, src);
				fwrite(buf, 4, 1, dst);
			}
			fclose(dst);
			fclose(src);
			return;
		}
		if (atom_size == 0)
			break; //0 atom size means to the end of file... if it's not the mdat chunk, we're done
		fseek(src, atom_size, SEEK_CUR);
	}
	fclose(src);
	@throw [NSException exceptionWithName:@"TSUnknownException" reason:@"Didn't find mdat chunk"  userInfo:nil];
}

- (NSError*)error {
	return export.error;
}

- (AVAssetExportSessionStatus)status {
	return export.status;
}

- (float)progress {
	return export.progress;
}
@end
