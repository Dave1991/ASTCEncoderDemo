//
//  ViewController.m
//  ASTCEncoderDemo
//
//  Created by forrest on 2022/3/31.
//

#import "ViewController.h"
#include "astcenc.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *astcDir = [docs[0] stringByAppendingString:@"/ASTC"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:astcDir]) {
        [[NSFileManager defaultManager] removeItemAtPath:astcDir error:nil];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:astcDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:astcDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSArray<NSString *> *pngList = [[NSBundle mainBundle] pathsForResourcesOfType:@"png" inDirectory:@"pngList"];
    int index = 0;
    for (NSString *pngPath in pngList) {
        [self compressImage:[UIImage imageWithContentsOfFile:pngPath] dstPath:[astcDir stringByAppendingFormat:@"/%d.astc", index]];
        ++index;
    }
}


- (void)compressImage:(UIImage *)image dstPath:(NSString *)dstPath {
    static const unsigned int thread_count = 1;
    static const unsigned int block_x = 6;
    static const unsigned int block_y = 6;
    static const unsigned int block_z = 1;
    static const astcenc_profile profile = ASTCENC_PRF_LDR;
    static const float quality = ASTCENC_PRE_MEDIUM;
    static const astcenc_swizzle swizzle {
        ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A
    };
    int imageWidth = (int)CGImageGetWidth(image.CGImage), imageHeight = (int)CGImageGetHeight(image.CGImage);
    // Compute the number of ASTC blocks in each dimension
    unsigned int block_count_x = (imageWidth + block_x - 1) / block_x;
    unsigned int block_count_y = (imageHeight + block_y - 1) / block_y;

    // ------------------------------------------------------------------------
    // Initialize the default configuration for the block size and quality
    astcenc_config config;
    config.block_x = block_x;
    config.block_y = block_y;
    config.profile = profile;

    astcenc_error status;
    status = astcenc_config_init(profile, block_x, block_y, block_z, quality, 0, &config);
    if (status != ASTCENC_SUCCESS)
    {
        NSLog(@"ERROR: Codec config init failed: %s", astcenc_get_error_string(status));
        return;
    }
    // ... power users can customize any config settings after calling
    // config_init() and before calling context alloc().

    // ------------------------------------------------------------------------
    // Create a context based on the configuration
    astcenc_context* context;
    status = astcenc_context_alloc(&config, thread_count, &context);
    if (status != ASTCENC_SUCCESS)
    {
        printf("ERROR: Codec context alloc failed: %s\n", astcenc_get_error_string(status));
        return;
    }

    // ------------------------------------------------------------------------
    // Compress the image
    astcenc_image astcImage;
    astcImage.dim_x = imageWidth;
    astcImage.dim_y = imageHeight;
    astcImage.dim_z = 1;
    astcImage.data_type = ASTCENC_TYPE_U8;
    uint8_t* slices = [self extractImagePixel:image];
    astcImage.data = reinterpret_cast<void**>(&slices);

    // Space needed for 16 bytes of output per compressed block
    size_t comp_len = block_count_x * block_count_y * 16;
    uint8_t* comp_data = new uint8_t[comp_len];

    status = astcenc_compress_image(context, &astcImage, &swizzle, comp_data, comp_len, 0);
    if (status != ASTCENC_SUCCESS)
    {
        printf("ERROR: Codec compress failed: %s\n", astcenc_get_error_string(status));
        return;
    }

    NSData *data = [NSData dataWithBytes:comp_data length:comp_len];
    [data writeToFile:dstPath atomically:YES];
}

- (unsigned char *)extractImagePixel:(UIImage *)image {
    CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage));
    const uint8_t* data = CFDataGetBytePtr(pixelData);
    
    int width = (int)image.size.width;
    int height = (int)image.size.height;
    
    size_t bitsPerPixel = CGImageGetBitsPerPixel(image.CGImage);
    printf("bitsPerPixel = %lu\n", bitsPerPixel);
    size_t gitsPerComponent = CGImageGetBitsPerComponent(image.CGImage);
    printf("gitsPerComponent = %lu\n", gitsPerComponent);
    
    uint8_t *imgData = (uint8_t *)malloc(width*height*4);
    memcpy(imgData, data, width*height*4);
    return imgData;
}

@end
