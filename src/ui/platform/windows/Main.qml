import QtQuick
import QtQuick.Window
import FluentUI
import "../../"

FluLauncher {
    id: app
    objectName: "Main"

    function prepareLiveReload() {
        const managedWindows = FluRouter.windows.slice()
        for (let i = managedWindows.length - 1; i >= 0; --i)
            FluRouter.removeWindow(managedWindows[i])
        FluApp.launcher = null
    }

    // Connections{
    //     target: FluTheme
    //     function onDarkModeChanged(){
    //         SettingsHelper.saveDarkMode(FluTheme.darkMode)
    //     }
    // }
    // Connections{
    //     target: FluApp
    //     function onUseSystemAppBarChanged(){
    //         SettingsHelper.saveUseSystemAppBar(FluApp.useSystemAppBar)
    //     }
    // }
    // Connections{
    //     target: TranslateHelper
    //     function onCurrentChanged(){
    //         SettingsHelper.saveLanguage(TranslateHelper.current)
    //     }
    // }
    Component.onCompleted: {
        // Network.openLog = false
        // Network.setInterceptor(function(param){
        //     param.addHeader("Token","000000000000000000000")
        // })
        FluApp.init(app,Qt.locale())
        // FluApp.windowIcon = "qrc:/example/res/image/favicon.ico"
        // FluApp.useSystemAppBar = SettingsHelper.getUseSystemAppBar()
        FluApp.useSystemAppBar = false
        // FluTheme.darkMode = SettingsHelper.getDarkMode()
        FluTheme.darkMode = false
        FluTheme.animationEnabled = true

        FluRouter.routes = {
            "/": Qt.resolvedUrl("Index.qml"),
        }
        var args = Qt.application.arguments
        if(args.length>=2 && args[1].startsWith("-crashed=")){
            FluRouter.navigate("/crash",{crashFilePath:args[1].replace("-crashed=","")})
        }else{
            FluRouter.navigate("/")
        }
        Updater.checkAutomatically()
    }

}
