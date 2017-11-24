#include <jni.h>
#include <string>
#include <stdlib.h>
#import "android/log.h"
#define  LOGI(...)  __android_log_print(ANDROID_LOG_INFO, "CTest", __VA_ARGS__)
static void test_memory_overrun()
{
    char *p = (char *)malloc(1);
    *(short*)p = 2;
    free(p);
}

static void test_strcpy_overrun()
{
    char *p = (char *)malloc(sizeof(char) * 5);
    strcpy(p, "hello");
}

static void test_memory_free_wild_pointer()
{
    char *p;
    free(p);
}

extern "C"
JNIEXPORT void
JNICALL
Java_com_sunshushu_test_MainActivity_fromIssue(
        JNIEnv *env,
        jobject /* this */) {

    test_memory_overrun();
    test_strcpy_overrun();
    test_memory_free_wild_pointer();
    LOGI("ctest: memory issues!");
}