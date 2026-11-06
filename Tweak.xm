#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <substrate.h>
#include <stdint.h>

// ==========================================
// 1. ตั้งค่าตัวแปรและสถานะการทำงาน
// ==========================================
static bool kEnableHighView = true;
static float kCustomFOV = 95.0f; // ค่าปกติของเกมอยู่ที่ประมาณ 60.0f (ยิ่งมากมุมมองยิ่งสูง/กว้าง)
static bool kEnableSkipRewardAd = true;

// ==========================================
// 2. ฟังก์ชันคำนวณ Base Address สำหรับ UnityFramework
// ==========================================
uintptr_t getUnityFrameworkBase() {
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (imageName && strstr(imageName, "UnityFramework.framework/UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    // Fallback กรณีเกมรวม Binary ไว้ในไฟล์หลัก
    return (uintptr_t)_dyld_get_image_header(0);
}

uintptr_t getRealOffset(uintptr_t rva) {
    uintptr_t base = getUnityFrameworkBase();
    return base + rva;
}

// ==========================================
// 3. ฮุคฟังก์ชัน Unity (IL2CPP) - มุมมองสูง & รางวัลโฆษณา
// ==========================================

// --- 3.1 มุมมองสูง (Camera.get_fieldOfView) ---
float (*orig_Camera_get_fieldOfView)(void *instance);
float hook_Camera_get_fieldOfView(void *instance) {
    if (instance != nullptr && kEnableHighView) {
        return kCustomFOV;
    }
    return orig_Camera_get_fieldOfView(instance);
}

// --- 3.2 บังคับสถานะว่าโฆษณาพร้อมใช้งานเสมอ ---
bool (*orig_AdsManager_IsRewardedAdReady)(void *instance);
bool hook_AdsManager_IsRewardedAdReady(void *instance) {
    if (kEnableSkipRewardAd) {
        return true;
    }
    return orig_AdsManager_IsRewardedAdReady(instance);
}

// ==========================================
// 4. ฮุคระดับ Objective-C สำหรับบล็อก SDK โฆษณา
// (Logos จะข้ามอัตโนมัติหากไม่มีคลาสนั้นในเกม ไม่ทำให้แอปเด้ง)
// ==========================================

// บล็อกการแสดงโฆษณาของ Google AdMob (GADRewardedAd) และสั่งจ่ายรางวัลทันที
%hook GADRewardedAd
- (void)presentFromRootViewController:(UIViewController *)rootViewController
             userDidEarnRewardHandler:(void (^)(void))userDidEarnRewardHandler {
    if (kEnableSkipRewardAd && userDidEarnRewardHandler) {
        // ข้ามการเปิดหน้าต่างโฆษณาและเรียก Callback รับรางวัลทันที
        userDidEarnRewardHandler();
        return;
    }
    %orig;
}
%end

// บล็อกการแสดงโฆษณาของ AppLovin MAX (MARewardedAd)
%hook MARewardedAd
- (void)showAdForPlacement:(NSString *)placement {
    if (kEnableSkipRewardAd) {
        return;
    }
    %orig;
}
%end

// ==========================================
// 5. จุดเริ่มต้นการทำงานเมื่อโหลด .dylib (%ctor)
// ==========================================
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // [สำคัญ] นำค่า RVA Offset จากไฟล์ dump.cs ของเกมเวอร์ชันล่าสุดมาใส่ตรงนี้
        // วิธีหาใน dump.cs:
        // 1. ค้นหา "public float get_fieldOfView()" ในคลาส UnityEngine.Camera
        // 2. ค้นหาฟังก์ชันเช็คโฆษณาในคลาส AdsManager / RewardAdController
        uintptr_t rva_Camera_get_fov = 0x0;       // ตัวอย่าง: 0x1A2B3C4 (ใส่ 0x0 ไว้เพื่อกันแอปเด้งหากยังไม่ได้ใส่ Offset จริง)
        uintptr_t rva_Ads_IsReady    = 0x0;       // ตัวอย่าง: 0x2B3C4D5

        if (rva_Camera_get_fov != 0x0) {
            MSHookFunction(
                (void *)getRealOffset(rva_Camera_get_fov),
                (void *)hook_Camera_get_fieldOfView,
                (void **)&orig_Camera_get_fieldOfView
            );
        }

        if (rva_Ads_IsReady != 0x0) {
            MSHookFunction(
                (void *)getRealOffset(rva_Ads_IsReady),
                (void *)hook_AdsManager_IsRewardedAdReady,
                (void **)&orig_AdsManager_IsRewardedAdReady
            );
        }

        // แสดงแจ้งเตือนเมื่อโหลดม็อดสำเร็จ
        UIWindow *foundWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        foundWindow = window;
                        break;
                    }
                }
            }
        }

        if (foundWindow && foundWindow.rootViewController) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Horrorfield Mod"
                                                                           message:@"โหลดระบบบล็อกโฆษณาและมุมมองสูงสำเร็จ"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"ตกลง" style:UIAlertActionStyleDefault handler:nil]];
            [foundWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}
