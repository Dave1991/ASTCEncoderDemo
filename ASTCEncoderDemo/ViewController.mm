//
//  ViewController.m
//  ASTCEncoderDemo
//
//  Created by forrest on 2022/3/31.
//

#import "ViewController.h"
#include "astcenc.h"
#include <array>

/**
 * @brief The payload stored in a compressed ASTC image.
 */
struct astc_compressed_image
{
    /** @brief The block width in texels. */
    unsigned int block_x;

    /** @brief The block height in texels. */
    unsigned int block_y;

    /** @brief The block depth in texels. */
    unsigned int block_z;

    /** @brief The image width in texels. */
    unsigned int dim_x;

    /** @brief The image height in texels. */
    unsigned int dim_y;

    /** @brief The image depth in texels. */
    unsigned int dim_z;

    /** @brief The binary data payload. */
    uint8_t* data;

    /** @brief The binary data length in bytes. */
    size_t data_len;
};

bool store_ktx_compressed_image(const astc_compressed_image& img, const char* filename, bool is_srgb);

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
    static const unsigned int thread_count = 4;
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

    astc_compressed_image compressedImg {block_x, block_y, block_z, astcImage.dim_x, astcImage.dim_y, astcImage.dim_z, comp_data, comp_len};
    store_ktx_compressed_image(compressedImg, dstPath.UTF8String, false);
    
    astcenc_context_free(context);
    delete[] comp_data;
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

struct ktx_header
{
    uint8_t magic[12];
    uint32_t endianness;                // should be 0x04030201; if it is instead 0x01020304, then the endianness of everything must be switched.
    uint32_t gl_type;                    // 0 for compressed textures, otherwise value from table 3.2 (page 162) of OpenGL 4.0 spec
    uint32_t gl_type_size;                // size of data elements to do endianness swap on (1=endian-neutral data)
    uint32_t gl_format;                    // 0 for compressed textures, otherwise value from table 3.3 (page 163) of OpenGL spec
    uint32_t gl_internal_format;        // sized-internal-format, corresponding to table 3.12 to 3.14 (pages 182-185) of OpenGL spec
    uint32_t gl_base_internal_format;    // unsized-internal-format: corresponding to table 3.11 (page 179) of OpenGL spec
    uint32_t pixel_width;                // texture dimensions; not rounded up to block size for compressed.
    uint32_t pixel_height;                // must be 0 for 1D textures.
    uint32_t pixel_depth;                // must be 0 for 1D, 2D and cubemap textures.
    uint32_t number_of_array_elements;    // 0 if not a texture array
    uint32_t number_of_faces;            // 6 for cubemaps, 1 for non-cubemaps
    uint32_t number_of_mipmap_levels;    // 0 or 1 for non-mipmapped textures; 0 indicates that auto-mipmap-gen should be done at load time.
    uint32_t bytes_of_key_value_data;    // size in bytes of the key-and-value area immediately following the header.
};

// magic 12-byte sequence that must appear at the beginning of every KTX file.
static uint8_t ktx_magic[12] {
    0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A
};

// Khronos enums
#define GL_RED                                      0x1903
#define GL_RG                                       0x8227
#define GL_RGB                                      0x1907
#define GL_RGBA                                     0x1908
#define GL_BGR                                      0x80E0
#define GL_BGRA                                     0x80E1
#define GL_LUMINANCE                                0x1909
#define GL_LUMINANCE_ALPHA                          0x190A

#define GL_UNSIGNED_BYTE                            0x1401
#define GL_UNSIGNED_SHORT                           0x1403
#define GL_HALF_FLOAT                               0x140B
#define GL_FLOAT                                    0x1406

#define GL_COMPRESSED_RGBA_ASTC_4x4                 0x93B0
#define GL_COMPRESSED_RGBA_ASTC_5x4                 0x93B1
#define GL_COMPRESSED_RGBA_ASTC_5x5                 0x93B2
#define GL_COMPRESSED_RGBA_ASTC_6x5                 0x93B3
#define GL_COMPRESSED_RGBA_ASTC_6x6                 0x93B4
#define GL_COMPRESSED_RGBA_ASTC_8x5                 0x93B5
#define GL_COMPRESSED_RGBA_ASTC_8x6                 0x93B6
#define GL_COMPRESSED_RGBA_ASTC_8x8                 0x93B7
#define GL_COMPRESSED_RGBA_ASTC_10x5                0x93B8
#define GL_COMPRESSED_RGBA_ASTC_10x6                0x93B9
#define GL_COMPRESSED_RGBA_ASTC_10x8                0x93BA
#define GL_COMPRESSED_RGBA_ASTC_10x10               0x93BB
#define GL_COMPRESSED_RGBA_ASTC_12x10               0x93BC
#define GL_COMPRESSED_RGBA_ASTC_12x12               0x93BD

#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4         0x93D0
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x4         0x93D1
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x5         0x93D2
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x5         0x93D3
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x6         0x93D4
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x5         0x93D5
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x6         0x93D6
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x8         0x93D7
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x5        0x93D8
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x6        0x93D9
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x8        0x93DA
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x10       0x93DB
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_12x10       0x93DC
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_12x12       0x93DD

#define GL_COMPRESSED_RGBA_ASTC_3x3x3_OES           0x93C0
#define GL_COMPRESSED_RGBA_ASTC_4x3x3_OES           0x93C1
#define GL_COMPRESSED_RGBA_ASTC_4x4x3_OES           0x93C2
#define GL_COMPRESSED_RGBA_ASTC_4x4x4_OES           0x93C3
#define GL_COMPRESSED_RGBA_ASTC_5x4x4_OES           0x93C4
#define GL_COMPRESSED_RGBA_ASTC_5x5x4_OES           0x93C5
#define GL_COMPRESSED_RGBA_ASTC_5x5x5_OES           0x93C6
#define GL_COMPRESSED_RGBA_ASTC_6x5x5_OES           0x93C7
#define GL_COMPRESSED_RGBA_ASTC_6x6x5_OES           0x93C8
#define GL_COMPRESSED_RGBA_ASTC_6x6x6_OES           0x93C9

#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_3x3x3_OES   0x93E0
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x3x3_OES   0x93E1
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4x3_OES   0x93E2
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4x4_OES   0x93E3
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x4x4_OES   0x93E4
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x5x4_OES   0x93E5
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x5x5_OES   0x93E6
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x5x5_OES   0x93E7
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x6x5_OES   0x93E8
#define GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x6x6_OES   0x93E9

struct format_entry
{
    unsigned int x;
    unsigned int y;
    unsigned int z;
    bool is_srgb;
    unsigned int format;
};

static const std::array<format_entry, 48> ASTC_FORMATS =
{{
    // 2D Linear RGB
    { 4,  4,  1, false, GL_COMPRESSED_RGBA_ASTC_4x4},
    { 5,  4,  1, false, GL_COMPRESSED_RGBA_ASTC_5x4},
    { 5,  5,  1, false, GL_COMPRESSED_RGBA_ASTC_5x5},
    { 6,  5,  1, false, GL_COMPRESSED_RGBA_ASTC_6x5},
    { 6,  6,  1, false, GL_COMPRESSED_RGBA_ASTC_6x6},
    { 8,  5,  1, false, GL_COMPRESSED_RGBA_ASTC_8x5},
    { 8,  6,  1, false, GL_COMPRESSED_RGBA_ASTC_8x6},
    { 8,  8,  1, false, GL_COMPRESSED_RGBA_ASTC_8x8},
    {10,  5,  1, false, GL_COMPRESSED_RGBA_ASTC_10x5},
    {10,  6,  1, false, GL_COMPRESSED_RGBA_ASTC_10x6},
    {10,  8,  1, false, GL_COMPRESSED_RGBA_ASTC_10x8},
    {10, 10,  1, false, GL_COMPRESSED_RGBA_ASTC_10x10},
    {12, 10,  1, false, GL_COMPRESSED_RGBA_ASTC_12x10},
    {12, 12,  1, false, GL_COMPRESSED_RGBA_ASTC_12x12},
    // 2D SRGB
    { 4,  4,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4},
    { 5,  4,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x4},
    { 5,  5,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x5},
    { 6,  5,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x5},
    { 6,  6,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x6},
    { 8,  5,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x5},
    { 8,  6,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x6},
    { 8,  8,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x8},
    {10,  5,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x5},
    {10,  6,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x6},
    {10,  8,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x8},
    {10, 10,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x10},
    {12, 10,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_12x10},
    {12, 12,  1,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_12x12},
    // 3D Linear RGB
    { 3,  3,  3, false, GL_COMPRESSED_RGBA_ASTC_3x3x3_OES},
    { 4,  3,  3, false, GL_COMPRESSED_RGBA_ASTC_4x3x3_OES},
    { 4,  4,  3, false, GL_COMPRESSED_RGBA_ASTC_4x4x3_OES},
    { 4,  4,  4, false, GL_COMPRESSED_RGBA_ASTC_4x4x4_OES},
    { 5,  4,  4, false, GL_COMPRESSED_RGBA_ASTC_5x4x4_OES},
    { 5,  5,  4, false, GL_COMPRESSED_RGBA_ASTC_5x5x4_OES},
    { 5,  5,  5, false, GL_COMPRESSED_RGBA_ASTC_5x5x5_OES},
    { 6,  5,  5, false, GL_COMPRESSED_RGBA_ASTC_6x5x5_OES},
    { 6,  6,  5, false, GL_COMPRESSED_RGBA_ASTC_6x6x5_OES},
    { 6,  6,  6, false, GL_COMPRESSED_RGBA_ASTC_6x6x6_OES},
    // 3D SRGB
    { 3,  3,  3,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_3x3x3_OES},
    { 4,  3,  3,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x3x3_OES},
    { 4,  4,  3,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4x3_OES},
    { 4,  4,  4,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4x4_OES},
    { 5,  4,  4,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x4x4_OES},
    { 5,  5,  4,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x5x4_OES},
    { 5,  5,  5,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x5x5_OES},
    { 6,  5,  5,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x5x5_OES},
    { 6,  6,  5,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x6x5_OES},
    { 6,  6,  6,  true, GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x6x6_OES}
}};

static unsigned int get_format(
    unsigned int x,
    unsigned int y,
    unsigned int z,
    bool is_srgb
) {
    for (auto& it : ASTC_FORMATS)
    {
        if ((it.x == x) && (it.y == y) && (it.z == z)  && (it.is_srgb == is_srgb))
        {
            return it.format;
        }
    }
    return 0;
}

/**
 * @brief Store a KTX compressed image using a local store routine.
 *
 * @param img        The image data to store.
 * @param filename   The name of the file to save.
 * @param is_srgb    @c true if this is an sRGB image, @c false if linear.
 *
 * @return @c true on error, @c false otherwise.
 */
bool store_ktx_compressed_image(
    const astc_compressed_image& img,
    const char* filename,
    bool is_srgb) {
    unsigned int fmt = get_format(img.block_x, img.block_y, img.block_z, is_srgb);

    ktx_header hdr;
    memcpy(hdr.magic, ktx_magic, 12);
    hdr.endianness = 0x04030201;
    hdr.gl_type = 0;
    hdr.gl_type_size = 1;
    hdr.gl_format = 0;
    hdr.gl_internal_format = fmt;
    hdr.gl_base_internal_format = GL_RGBA;
    hdr.pixel_width = img.dim_x;
    hdr.pixel_height = img.dim_y;
    hdr.pixel_depth = (img.dim_z == 1) ? 0 : img.dim_z;
    hdr.number_of_array_elements = 0;
    hdr.number_of_faces = 1;
    hdr.number_of_mipmap_levels = 1;
    hdr.bytes_of_key_value_data = 0;

    size_t expected = sizeof(ktx_header) + 4 + img.data_len;
    size_t actual = 0;

    FILE *wf = fopen(filename, "wb");
    if (!wf)
    {
        return true;
    }

    actual += fwrite(&hdr, 1, sizeof(ktx_header), wf);
    actual += fwrite(&img.data_len, 1, 4, wf);
    actual += fwrite(img.data, 1, img.data_len, wf);
    fclose(wf);

    if (actual != expected)
    {
        return true;
    }

    return false;
}

@end
