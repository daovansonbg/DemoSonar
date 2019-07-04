//
//  AppDelegate.swift
//  mastersns
//
//  Created by tatsuya noguchi on 2017/07/21.
//  Copyright © 2017年 newbees. All rights reserved.
//

import UIKit
import FBSDKCoreKit
import FBSDKLoginKit.FBSDKLoginManager
import SwiftyStoreKit
import TwitterKit
import GoogleSignIn
import UserNotifications
import Firebase

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, WillEnterForegroundNotificationSendProtocol {
    static var shared : AppDelegate { return UIApplication.shared.delegate as! AppDelegate }
    var window: UIWindow?
    var gAoccaPurposeList:[AoccaPurpose] = [AoccaPurpose]()
    var gLastAocca:LastAocca = LastAocca(type: nil,purpose: nil)
    var selectSimpleName:String?
    var gLoginUseeInfo:loginUserInfo = loginUserInfo(nickname: "",gender: Gender(isMale: true))
    var purchaseManager: PurchaseManager = PurchaseManager()
    let gcmMessageIDKey = "gcm.message_id"
    var jumpPage: String?
    var pushData: CustomData?
    var urlSchemeType : String?
    var urlSchemeContent : String?
    var isBack :Bool?
    var timer: Timer!
    var schemeTimer: Timer!
    
    func anyGetString(value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        return nil
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        //初期処理
        self.initSetting(application: application, launchOptions: launchOptions)
        //初期処理は後でまとめる。
        ZipManager.shared.removeAndCopyDocument()
        
        // Adjustのセットアップ(checkUuidApiがsuucessの時、Adustを実行しているので、Splash生成前に行う)
        AdjustManager.shared.setup()
        if let userInfo = launchOptions?  [UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable : Any] {
            //            debugLog(userInfo)
            if userInfo[AnyHashable("custom_data")] != nil {
                let customData = userInfo[AnyHashable("custom_data")]
                let record:String? = anyGetString(value: customData)
                let decoder: JSONDecoder = JSONDecoder()
                do {
                    self.pushData = try decoder.decode(CustomData.self, from: record!.data(using: .utf8)!)
                    self.jumpPage = self.pushData?.to
                } catch {
                    debugLog(error)
                }
                self.isBack = false // バックグラウンドからの復帰かのフラグ
            }
        }
        //Window生成
        self.createWindow()
        
        // Restore finishしていないtransactionをAoccaサーバーに投げてOKの場合、finishTransaction処理を行う
        if SecretCodeManager.shared.exists {
            purchaseManager.checkCompletedPurchase()
        }
        FirebaseApp.configure()
        
        AnalyticsConfiguration.shared().setAnalyticsCollectionEnabled(false)
        Messaging.messaging().delegate = self as MessagingDelegate
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    ///Windowとそれに付属するViewの生成
    func createWindow() {
        self.window = UIWindow()
        TextFieldLockViewManager.shared.createView(view: AppDelegate.shared.window!)
        AppNotificationManager.shared.createView(view: AppDelegate.shared.window!)
        DialogManager.shared.createView(view: AppDelegate.shared.window!)
        IndicatorManager.shared.createView(view: AppDelegate.shared.window!)
        ToastManager.shared.createView(view: AppDelegate.shared.window!)
        
        // Splashの起動、かつ checkSecretCodeApi || UuidApi を実行し、ブートシーケンスを行う
        ViewUtil.changeRootVC(vc: ViewUtil.loadStoryboardInitialVC(storyboard: "Splash"))
        self.window!.makeKeyAndVisible()
    }
    
    ///初期処理
    func initSetting(application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        TwitterAuth.initSetting()
        FacebookAuth.initSetting(application: application, launchOptions: launchOptions)
        AoccaImageViewManager.shared.startTimer()
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        //self.sendWillEnterForegroundNotification()
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        FBSDKAppEvents.activateApp()
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
    }
    
    ///スキームで起動された時
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        let sourceApplication = options[UIApplication.OpenURLOptionsKey.sourceApplication]
        let annotation = options[UIApplication.OpenURLOptionsKey.annotation]
        if url.absoluteString.regMatch(pattern: "^fb\\w+:") {
            return FBSDKApplicationDelegate.sharedInstance().application(app, open: url as URL?, sourceApplication: sourceApplication as! String, annotation: annotation)
        } else if url.absoluteString.regMatch(pattern: "^twitterkit-") {
            return Twitter.sharedInstance().application(app, open: url, options: options)
        } else if url.absoluteString.regMatch(pattern: "com.googleusercontent.apps") {
            return GIDSignIn.sharedInstance()!.handle(url, sourceApplication: sourceApplication as! String, annotation: annotation)
        } else if url.absoluteString.hasPrefix(YahooAuth.shared.urlScheme) {
            YahooAuth.shared.callBackEvent(url: url)
        }
        return false
    }
    
    ///デバイストークン取得
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // fcmを利用するため、送信しない
        DeviceTokenManager.shared.resend()
    }
    ///通知取得時処理
    //    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    //        completionHandler(.noData)
    //    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {
        if let messageID = userInfo["gcm.message_id"] {
            debugLog("Message ID: \(messageID)")
        }
    }
    ///メモリー警告
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        ApiImageView.deleteCacheOnMemoryWarning()
    }
    //Universal link
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            let webpageURL = userActivity.webpageURL!
            if !handleUniversalLink(URL: webpageURL) {
                // コンテンツをアプリで開けない場合は、Safariに戻す
                AppUtil.openURL(url: webpageURL)
                return false
            }
        }
        return true
    }
    func handleUniversalLink(URL url: URL) -> Bool {
        if let components = NSURLComponents(url: url as URL, resolvingAgainstBaseURL: true), let host = components.host {
            var dict = [String:String]()
            if let queryItems = components.queryItems {
                for item in queryItems {
                    dict[item.name] = item.value!
                }
            }
            if dict.isEmpty { return false }
            switch host {
            case AppConst.webHost:
                self.urlSchemeType = dict["type"] ?? ""
                self.urlSchemeContent = dict["type_id"] ?? ""
                self.schemeTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector:  #selector(AppDelegate.postCheckUrlScheme), userInfo: nil, repeats: true)
                return true
            default:
                return false
            }
            
        }
        return false
    }
    @objc func postCheckUrlScheme () {
        if MainTBC.current != nil && MainTBC.current.isViewLoaded {
            NotificationCenter.default.post(key: .CheckUrlScheme)
            self.schemeTimer.invalidate()
        }
    }
}

// [START ios_10_message_handling]
@available(iOS 10, *)
extension AppDelegate : UNUserNotificationCenterDelegate {
    
    // Receive displayed notifications for iOS 10 devices.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        // With swizzling disabled you must let Messaging know about the message, for Analytics
        // Messaging.messaging().appDidReceiveMessage(userInfo)
        // Print message ID.
        // この時はAPPが表示している。
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
            if userInfo[AnyHashable("custom_data")] != nil {
                let customData = userInfo[AnyHashable("custom_data")]
                let record:String? = anyGetString(value: customData)
                let decoder: JSONDecoder = JSONDecoder()
                do {
                    self.pushData = try decoder.decode(CustomData.self, from: record!.data(using: .utf8)!)
                    self.isBack = false // バックグラウンドからの復帰かのフラグ
                    TabBadge.setKeepBdage(number: (self.pushData?.footerBadge?.fromkeepCnt)!)
                    TabBadge.setMessageBdage(number: (self.pushData?.footerBadge?.msgCnt)!)
                    TabBadge.setFootprintBdage(number: (self.pushData?.footerBadge?.footprintasCnt)!)
                    TabBadge.setMyPageBdage(number: (self.pushData?.footerBadge?.infoCnt)!)
                    UIApplication.shared.applicationIconBadgeNumber = TabBadge.getAllBadgeNumber()
                    if (self.pushData?.footerBadge?.msgCnt)! > 0 {
                        NotificationCenter.default.post(key: .reloadMessageList)
                    }
                } catch {
                    debugLog(error)
                }
            }
            
        }
        
        // Print full message.
        debugLog(userInfo)
        
        // Change this to your preferred presentation option
        completionHandler([])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if userInfo[AnyHashable("custom_data")] != nil {
            let customData = userInfo[AnyHashable("custom_data")]
            let record:String? = anyGetString(value: customData)
            let decoder: JSONDecoder = JSONDecoder()
            do {
                self.pushData = try decoder.decode(CustomData.self, from: record!.data(using: .utf8)!)
                self.isBack = true // バックグラウンドからの復帰かのフラグ
                self.jumpPage = self.pushData?.to
                
            } catch {
                debugLog(error)
            }
            self.timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(AppDelegate.postNotificationTimer), userInfo: nil, repeats: true)
        }
        
        // Print full message.
        debugLog(userInfo)
        
        completionHandler()
    }
    
    @objc func postNotificationTimer () {
        if MainTBC.current != nil && MainTBC.current.isViewLoaded {
            NotificationCenter.default.post(key: .PushNotification)
            self.timer.invalidate()
        }
    }
    
    func resetPush() {
        if self.pushData != nil {
            self.jumpPage = nil
            self.pushData = nil
            self.isBack = nil
            self.timer.invalidate()
        }
    }
}
// [END ios_10_message_handling]

extension AppDelegate : MessagingDelegate {
    // [START refresh_token]
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        debugLog("Firebase registration token: \(fcmToken)")
        
        let dataDict:[String: String] = ["token": fcmToken]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
        // TODO: If necessary send token to application server.
        DeviceTokenManager.shared.sendtDeviceToken(fcmToken: fcmToken)
        // Note: This callback is fired at each app startup and whenever a new token is generated.
    }
    // [END refresh_token]
    // [START ios_10_data_message]
    // Receive data messages on iOS 10+ directly from FCM (bypassing APNs) when the app is in the foreground.
    // To enable direct data messages, you can set Messaging.messaging().shouldEstablishDirectChannel to true.
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        debugLog("Received data message: \(remoteMessage.appData)")
    }
    // [END ios_10_data_message]
}
