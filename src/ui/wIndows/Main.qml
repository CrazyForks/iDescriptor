import QtQuick 2.15
import QtQuick.Window 2.15
// import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import FluentUI 1.0
import "../"

FluLauncher {
    id: app
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
        var indexUrl = Qt.resolvedUrl("Index.qml")
        console.log("Index URL =", indexUrl)

        FluRouter.routes = {
            "/": indexUrl
        }
        var args = Qt.application.arguments
        if(args.length>=2 && args[1].startsWith("-crashed=")){
            FluRouter.navigate("/crash",{crashFilePath:args[1].replace("-crashed=","")})
        }else{
            FluRouter.navigate("/")
        }
    }

}
