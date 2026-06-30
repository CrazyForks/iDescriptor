import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../base"
import "../+windows"

ToolWindow {
    id: root
    width: 800
    height: 600
    visible: true
    title: qsTr("Query MobileGestalt - iDescriptor")

    function selectedKeys() {
        var keys = []
        for (var i = 0; i < keysModel.count; ++i) {
            var item = keysModel.get(i)
            if (item.checked) keys.push(item.key)
        }
        return keys
    }

    function formatResults(results) {
        var output = "MobileGestalt Query Results\n"
        output += "=" + "=".repeat(50) + "\n\n"
        var keys = Object.keys(results || {})
        if (keys.length === 0) {
            output += "No results found.\n"
        } else {
            for (var i = 0; i < keys.length; ++i) {
                var k = keys[i]
                output += "Key: " + k + "\n"
                output += "Value: " + results[k] + "\n"
                output += "-".repeat(30) + "\n"
            }
        }
        return output
    }

    Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: qsTr("This tool lets you query MobileGestalt keys, which provide various device information.")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            GroupBox {
                title: qsTr("Select MobileGestalt Keys")
                Layout.fillWidth: true
                Layout.fillHeight: false

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Button {
                            text: qsTr("Select All")
                            onClicked: {
                                for (var i = 0; i < keysModel.count; ++i)
                                    keysModel.setProperty(i, "checked", true)
                            }
                        }

                        Button {
                            text: qsTr("Clear All")
                            onClicked: {
                                for (var i = 0; i < keysModel.count; ++i)
                                    keysModel.setProperty(i, "checked", false)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
                        Layout.fillHeight: false

                        ListView {
                            id: keysList
                            anchors.fill: parent
                            model: keysModel
                            clip: true
                            delegate: CheckBox {
                                text: model.key
                                checked: model.checked
                                onToggled: keysModel.setProperty(index, "checked", checked)
                            }
                        }
                    }
                }
            }

            Button {
                text: qsTr("Query MobileGestalt")
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    var keys = selectedKeys()
                    if (keys.length === 0) {
                        statusLabel.text = "Please select at least one key to query."
                        statusLabel.color = "#ff6b6b"
                        return
                    }
                    statusLabel.text = "Querying " + keys.length + " key(s)..."
                    statusLabel.color = "#4CAF50"
                    device.service_manager.query_mobilegestalt(keys)
                }
            }

            Label {
                id: statusLabel
                text: qsTr("Select keys and click Query to begin")
                color: "#666"
                font.italic: true
                Layout.fillWidth: true
            }

            GroupBox {
                title: qsTr("Query Results")
                Layout.fillWidth: true
                Layout.fillHeight: true

                TextArea {
                    id: outputText
                    readOnly: true
                    placeholderText: qsTr("results will appear here...")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }
    }

    Connections {
        target: device.service_manager
        function onMobilegestalt_info_retrieved(info) {
            outputText.text = formatResults(info)
            var n = Object.keys(info || {}).length 
            statusLabel.text = qsTr("Query completed. Found %n result(s).","",n)
            statusLabel.color = "#4CAF50"
        }
    }

    // Credits ->
    // https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/diagnostics.py
    ListModel {
        id: keysModel
        ListElement { key: "3GProximityCapability"; checked: false }
        ListElement { key: "3GVeniceCapability"; checked: false }
        ListElement { key: "3Gvenice"; checked: false }
        ListElement { key: "3d-imagery"; checked: false }
        ListElement { key: "3d-maps"; checked: false }
        ListElement { key: "64-bit"; checked: false }
        ListElement { key: "720p"; checked: false }
        ListElement { key: "720pPlaybackCapability"; checked: false }
        ListElement { key: "APNCapability"; checked: false }
        ListElement { key: "ARM64ExecutionCapability"; checked: false }
        ListElement { key: "ARMV6ExecutionCapability"; checked: false }
        ListElement { key: "ARMV7ExecutionCapability"; checked: false }
        ListElement { key: "ARMV7SExecutionCapability"; checked: false }
        ListElement { key: "ASTC"; checked: false }
        ListElement { key: "AWDID"; checked: false }
        ListElement { key: "AWDLCapability"; checked: false }
        ListElement { key: "AccelerometerCapability"; checked: false }
        ListElement { key: "AccessibilityCapability"; checked: false }
        ListElement { key: "AcousticID"; checked: false }
        ListElement { key: "ActivationProtocol"; checked: false }
        ListElement { key: "ActiveWirelessTechnology"; checked: false }
        ListElement { key: "ActuatorResonantFrequency"; checked: false }
        ListElement { key: "AdditionalTextTonesCapability"; checked: false }
        ListElement { key: "AggregateDevicePhotoZoomFactor"; checked: false }
        ListElement { key: "AggregateDeviceVideoZoomFactor"; checked: false }
        ListElement { key: "AirDropCapability"; checked: false }
        ListElement { key: "AirDropRestriction"; checked: false }
        ListElement { key: "AirplaneMode"; checked: false }
        ListElement { key: "AirplayMirroringCapability"; checked: false }
        ListElement { key: "AllDeviceCapabilities"; checked: false }
        ListElement { key: "Allow32BitApps"; checked: false }
        ListElement { key: "AllowOnlyATVCPSDKApps"; checked: false }
        ListElement { key: "AllowYouTube"; checked: false }
        ListElement { key: "AllowYouTubePlugin"; checked: false }
        ListElement { key: "AmbientLightSensorCapability"; checked: false }
        ListElement { key: "AmbientLightSensorSerialNumber"; checked: false }
        ListElement { key: "ApNonce"; checked: false }
        ListElement { key: "ApNonceRetrieve"; checked: false }
        ListElement { key: "AppCapacityTVOS"; checked: false }
        ListElement { key: "AppStore"; checked: false }
        ListElement { key: "AppStoreCapability"; checked: false }
        ListElement { key: "AppleInternalInstallCapability"; checked: false }
        ListElement { key: "AppleNeuralEngineSubtype"; checked: false }
        ListElement { key: "ApplicationInstallationCapability"; checked: false }
        ListElement { key: "ArcModuleSerialNumber"; checked: false }
        ListElement { key: "ArrowChipID"; checked: false }
        ListElement { key: "ArrowUniqueChipID"; checked: false }
        ListElement { key: "ArtworkTraits"; checked: false }
        ListElement { key: "AssistantCapability"; checked: false }
        ListElement { key: "AudioPlaybackCapability"; checked: false }
        ListElement { key: "AutoFocusCameraCapability"; checked: false }
        ListElement { key: "AvailableDisplayZoomSizes"; checked: false }
        ListElement { key: "BacklightCapability"; checked: false }
        ListElement { key: "BasebandAPTimeSync"; checked: false }
        ListElement { key: "BasebandBoardSnum"; checked: false }
        ListElement { key: "BasebandCertId"; checked: false }
        ListElement { key: "BasebandChipId"; checked: false }
        ListElement { key: "BasebandChipset"; checked: false }
        ListElement { key: "BasebandClass"; checked: false }
        ListElement { key: "BasebandFirmwareManifestData"; checked: false }
        ListElement { key: "BasebandFirmwareUpdateInfo"; checked: false }
        ListElement { key: "BasebandFirmwareVersion"; checked: false }
        ListElement { key: "BasebandKeyHashInformation"; checked: false }
        ListElement { key: "BasebandPostponementStatus"; checked: false }
        ListElement { key: "BasebandPostponementStatusBlob"; checked: false }
        ListElement { key: "BasebandRegionSKU"; checked: false }
        ListElement { key: "BasebandRegionSKURadioTechnology"; checked: false }
        ListElement { key: "BasebandSecurityInfoBlob"; checked: false }
        ListElement { key: "BasebandSerialNumber"; checked: false }
        ListElement { key: "BasebandSkeyId"; checked: false }
        ListElement { key: "BasebandStatus"; checked: false }
        ListElement { key: "BasebandUniqueId"; checked: false }
        ListElement { key: "BatteryCurrentCapacity"; checked: false }
        ListElement { key: "BatteryIsCharging"; checked: false }
        ListElement { key: "BatteryIsFullyCharged"; checked: false }
        ListElement { key: "BatterySerialNumber"; checked: false }
        ListElement { key: "BlueLightReductionSupported"; checked: false }
        ListElement { key: "BluetoothAddress"; checked: false }
        ListElement { key: "BluetoothAddressData"; checked: false }
        ListElement { key: "BluetoothCapability"; checked: false }
        ListElement { key: "BluetoothLE2Capability"; checked: false }
        ListElement { key: "BluetoothLECapability"; checked: false }
        ListElement { key: "BoardId"; checked: false }
        ListElement { key: "BoardRevision"; checked: false }
        ListElement { key: "BootManifestHash"; checked: false }
        ListElement { key: "BootNonce"; checked: false }
        ListElement { key: "BridgeBuild"; checked: false }
        ListElement { key: "BridgeRestoreVersion"; checked: false }
        ListElement { key: "BuddyLanguagesAnimationRequiresOptimization"; checked: false }
        ListElement { key: "BuildID"; checked: false }
        ListElement { key: "BuildVersion"; checked: false }
        ListElement { key: "C2KDeviceCapability"; checked: false }
        ListElement { key: "CPUArchitecture"; checked: false }
        ListElement { key: "CPUSubType"; checked: false }
        ListElement { key: "CPUType"; checked: false }
        ListElement { key: "CallForwardingCapability"; checked: false }
        ListElement { key: "CallWaitingCapability"; checked: false }
        ListElement { key: "CallerIDCapability"; checked: false }
        ListElement { key: "CameraAppUIVersion"; checked: false }
        ListElement { key: "CameraCapability"; checked: false }
        ListElement { key: "CameraFlashCapability"; checked: false }
        ListElement { key: "CameraFrontFlashCapability"; checked: false }
        ListElement { key: "CameraHDR2Capability"; checked: false }
        ListElement { key: "CameraHDRVersion"; checked: false }
        ListElement { key: "CameraLiveEffectsCapability"; checked: false }
        ListElement { key: "CameraMaxBurstLength"; checked: false }
        ListElement { key: "CameraRestriction"; checked: false }
        ListElement { key: "CarrierBundleInfoArray"; checked: false }
        ListElement { key: "CarrierInstallCapability"; checked: false }
        ListElement { key: "CellBroadcastCapability"; checked: false }
        ListElement { key: "CellularDataCapability"; checked: false }
        ListElement { key: "CellularTelephonyCapability"; checked: false }
        ListElement { key: "CertificateProductionStatus"; checked: false }
        ListElement { key: "CertificateSecurityMode"; checked: false }
        ListElement { key: "ChipID"; checked: false }
        ListElement { key: "CloudPhotoLibraryCapability"; checked: false }
        ListElement { key: "CoastlineGlowRenderingCapability"; checked: false }
        ListElement { key: "CompassCalibration"; checked: false }
        ListElement { key: "CompassCalibrationDictionary"; checked: false }
        ListElement { key: "CompassType"; checked: false }
        ListElement { key: "ComputerName"; checked: false }
        ListElement { key: "ConferenceCallType"; checked: false }
        ListElement { key: "ConfigNumber"; checked: false }
        ListElement { key: "ContainsCellularRadioCapability"; checked: false }
        ListElement { key: "ContinuityCapability"; checked: false }
        ListElement { key: "CoreRoutineCapability"; checked: false }
        ListElement { key: "CoverglassSerialNumber"; checked: false }
        ListElement { key: "DMin"; checked: false }
        ListElement { key: "DataPlanCapability"; checked: false }
        ListElement { key: "DebugBoardRevision"; checked: false }
        ListElement { key: "DelaySleepForHeadsetClickCapability"; checked: false }
        ListElement { key: "DesenseBuild"; checked: false }
        ListElement { key: "DeviceAlwaysPrewarmActuator"; checked: false }
        ListElement { key: "DeviceBackGlassMaterial"; checked: false }
        ListElement { key: "DeviceBackingColor"; checked: false }
        ListElement { key: "DeviceBrand"; checked: false }
        ListElement { key: "DeviceClass"; checked: false }
        ListElement { key: "DeviceClassNumber"; checked: false }
        ListElement { key: "DeviceColor"; checked: false }
        ListElement { key: "DeviceColorMapPolicy"; checked: false }
        ListElement { key: "DeviceCornerRadius"; checked: false }
        ListElement { key: "DeviceCoverGlassColor"; checked: false }
        ListElement { key: "DeviceCoverGlassMaterial"; checked: false }
        ListElement { key: "DeviceCoverMaterial"; checked: false }
        ListElement { key: "DeviceEnclosureColor"; checked: false }
        ListElement { key: "DeviceEnclosureMaterial"; checked: false }
        ListElement { key: "DeviceEnclosureRGBColor"; checked: false }
        ListElement { key: "DeviceHasAggregateCamera"; checked: false }
        ListElement { key: "DeviceHousingColor"; checked: false }
        ListElement { key: "DeviceIsMuseCapable"; checked: false }
        ListElement { key: "DeviceKeyboardCalibration"; checked: false }
        ListElement { key: "DeviceLaunchTimeLimitScale"; checked: false }
        ListElement { key: "DeviceName"; checked: false }
        ListElement { key: "DeviceNameString"; checked: false }
        ListElement { key: "DevicePrefers3DBuildingStrokes"; checked: false }
        ListElement { key: "DevicePrefersBuildingStrokes"; checked: false }
        ListElement { key: "DevicePrefersCheapTrafficShaders"; checked: false }
        ListElement { key: "DevicePrefersProceduralAntiAliasing"; checked: false }
        ListElement { key: "DevicePrefersTrafficAlpha"; checked: false }
        ListElement { key: "DeviceProximityCapability"; checked: false }
        ListElement { key: "DeviceRGBColor"; checked: false }
        ListElement { key: "DeviceRequiresPetalOptimization"; checked: false }
        ListElement { key: "DeviceRequiresProximityAmeliorations"; checked: false }
        ListElement { key: "DeviceRequiresSoftwareBrightnessCalculations"; checked: false }
        ListElement { key: "DeviceSceneUpdateTimeLimitScale"; checked: false }
        ListElement { key: "DeviceSubBrand"; checked: false }
        ListElement { key: "DeviceSupports1080p"; checked: false }
        ListElement { key: "DeviceSupports3DImagery"; checked: false }
        ListElement { key: "DeviceSupports3DMaps"; checked: false }
        ListElement { key: "DeviceSupports3rdPartyHaptics"; checked: false }
        ListElement { key: "DeviceSupports4G"; checked: false }
        ListElement { key: "DeviceSupports4k"; checked: false }
        ListElement { key: "DeviceSupports64Bit"; checked: false }
        ListElement { key: "DeviceSupports720p"; checked: false }
        ListElement { key: "DeviceSupports9Pin"; checked: false }
        ListElement { key: "DeviceSupportsAOP"; checked: false }
        ListElement { key: "DeviceSupportsARKit"; checked: false }
        ListElement { key: "DeviceSupportsASTC"; checked: false }
        ListElement { key: "DeviceSupportsAdaptiveMapsUI"; checked: false }
        ListElement { key: "DeviceSupportsAlwaysListening"; checked: false }
        ListElement { key: "DeviceSupportsAlwaysOnCompass"; checked: false }
        ListElement { key: "DeviceSupportsAlwaysOnTime"; checked: false }
        ListElement { key: "DeviceSupportsApplePencil"; checked: false }
        ListElement { key: "DeviceSupportsAutoLowLightVideo"; checked: false }
        ListElement { key: "DeviceSupportsAvatars"; checked: false }
        ListElement { key: "DeviceSupportsBatteryModuleAuthentication"; checked: false }
        ListElement { key: "DeviceSupportsBerkelium2"; checked: false }
        ListElement { key: "DeviceSupportsCCK"; checked: false }
        ListElement { key: "DeviceSupportsCameraCaptureOnTouchDown"; checked: false }
        ListElement { key: "DeviceSupportsCameraDeferredProcessing"; checked: false }
        ListElement { key: "DeviceSupportsCameraHaptics"; checked: false }
        ListElement { key: "DeviceSupportsCarIntegration"; checked: false }
        ListElement { key: "DeviceSupportsCinnamon"; checked: false }
        ListElement { key: "DeviceSupportsClosedLoopHaptics"; checked: false }
        ListElement { key: "DeviceSupportsCrudeProx"; checked: false }
        ListElement { key: "DeviceSupportsDClr"; checked: false }
        ListElement { key: "DeviceSupportsDoNotDisturbWhileDriving"; checked: false }
        ListElement { key: "DeviceSupportsELabel"; checked: false }
        ListElement { key: "DeviceSupportsEnhancedAC3"; checked: false }
        ListElement { key: "DeviceSupportsEnvironmentalDosimetry"; checked: false }
        ListElement { key: "DeviceSupportsExternalHDR"; checked: false }
        ListElement { key: "DeviceSupportsFloorCounting"; checked: false }
        ListElement { key: "DeviceSupportsHDRDeferredProcessing"; checked: false }
        ListElement { key: "DeviceSupportsHMEInARKit"; checked: false }
        ListElement { key: "DeviceSupportsHaptics"; checked: false }
        ListElement { key: "DeviceSupportsHardwareDetents"; checked: false }
        ListElement { key: "DeviceSupportsHeartHealthAlerts"; checked: false }
        ListElement { key: "DeviceSupportsHeartRateVariability"; checked: false }
        ListElement { key: "DeviceSupportsHiResBuildings"; checked: false }
        ListElement { key: "DeviceSupportsLineIn"; checked: false }
        ListElement { key: "DeviceSupportsLiquidDetection_CorrosionMitigation"; checked: false }
        ListElement { key: "DeviceSupportsLivePhotoAuto"; checked: false }
        ListElement { key: "DeviceSupportsLongFormAudio"; checked: false }
        ListElement { key: "DeviceSupportsMapsBlurredUI"; checked: false }
        ListElement { key: "DeviceSupportsMapsOpticalHeading"; checked: false }
        ListElement { key: "DeviceSupportsMomentCapture"; checked: false }
        ListElement { key: "DeviceSupportsNFC"; checked: false }
        ListElement { key: "DeviceSupportsNavigation"; checked: false }
        ListElement { key: "DeviceSupportsNewton"; checked: false }
        ListElement { key: "DeviceSupportsOnDemandPhotoAnalysis"; checked: false }
        ListElement { key: "DeviceSupportsP3ColorspaceVideoRecording"; checked: false }
        ListElement { key: "DeviceSupportsPeriodicALSUpdates"; checked: false }
        ListElement { key: "DeviceSupportsPhotosLocalLight"; checked: false }
        ListElement { key: "DeviceSupportsPortraitIntensityAdjustments"; checked: false }
        ListElement { key: "DeviceSupportsPortraitLightEffectFilters"; checked: false }
        ListElement { key: "DeviceSupportsRGB10"; checked: false }
        ListElement { key: "DeviceSupportsRaiseToSpeak"; checked: false }
        ListElement { key: "DeviceSupportsSiDP"; checked: false }
        ListElement { key: "DeviceSupportsSideButtonClickSpeed"; checked: false }
        ListElement { key: "DeviceSupportsSimplisticRoadMesh"; checked: false }
        ListElement { key: "DeviceSupportsSingleCameraPortrait"; checked: false }
        ListElement { key: "DeviceSupportsSiriBargeIn"; checked: false }
        ListElement { key: "DeviceSupportsSiriSpeaks"; checked: false }
        ListElement { key: "DeviceSupportsSiriSpokenMessages"; checked: false }
        ListElement { key: "DeviceSupportsSpatialOverCapture"; checked: false }
        ListElement { key: "DeviceSupportsStereoAudioRecording"; checked: false }
        ListElement { key: "DeviceSupportsStudioLightPortraitPreview"; checked: false }
        ListElement { key: "DeviceSupportsSwimmingWorkouts"; checked: false }
        ListElement { key: "DeviceSupportsTapToWake"; checked: false }
        ListElement { key: "DeviceSupportsTelephonyOverUSB"; checked: false }
        ListElement { key: "DeviceSupportsTethering"; checked: false }
        ListElement { key: "DeviceSupportsToneMapping"; checked: false }
        ListElement { key: "DeviceSupportsUSBTypeC"; checked: false }
        ListElement { key: "DeviceSupportsVSHCompensation"; checked: false }
        ListElement { key: "DeviceSupportsVoiceOverCanUseSiriVoice"; checked: false }
        ListElement { key: "DeviceSupportsWebkit"; checked: false }
        ListElement { key: "DeviceSupportsWirelessSplitting"; checked: false }
        ListElement { key: "DeviceSupportsYCbCr10"; checked: false }
        ListElement { key: "DeviceVariant"; checked: false }
        ListElement { key: "DeviceVariantGuess"; checked: false }
        ListElement { key: "DiagData"; checked: false }
        ListElement { key: "DictationCapability"; checked: false }
        ListElement { key: "DieId"; checked: false }
        ListElement { key: "DiskUsage"; checked: false }
        ListElement { key: "DisplayDriverICChipID"; checked: false }
        ListElement { key: "DisplayFCCLogosViaSoftwareCapability"; checked: false }
        ListElement { key: "DisplayMirroringCapability"; checked: false }
        ListElement { key: "DisplayPortCapability"; checked: false }
        ListElement { key: "DualSIMActivationPolicyCapable"; checked: false }
        ListElement { key: "EUICCChipID"; checked: false }
        ListElement { key: "EffectiveProductionStatus"; checked: false }
        ListElement { key: "EffectiveProductionStatusAp"; checked: false }
        ListElement { key: "EffectiveProductionStatusSEP"; checked: false }
        ListElement { key: "EffectiveSecurityMode"; checked: false }
        ListElement { key: "EffectiveSecurityModeAp"; checked: false }
        ListElement { key: "EffectiveSecurityModeSEP"; checked: false }
        ListElement { key: "EncodeAACCapability"; checked: false }
        ListElement { key: "EncryptedDataPartitionCapability"; checked: false }
        ListElement { key: "EnforceCameraShutterClick"; checked: false }
        ListElement { key: "EnforceGoogleMail"; checked: false }
        ListElement { key: "EthernetMacAddress"; checked: false }
        ListElement { key: "EthernetMacAddressData"; checked: false }
        ListElement { key: "ExplicitContentRestriction"; checked: false }
        ListElement { key: "ExternalChargeCapability"; checked: false }
        ListElement { key: "ExternalPowerSourceConnected"; checked: false }
        ListElement { key: "FDRSealingStatus"; checked: false }
        ListElement { key: "FMFAllowed"; checked: false }
        ListElement { key: "FaceTimeBackCameraTemporalNoiseReductionMode"; checked: false }
        ListElement { key: "FaceTimeBitRate2G"; checked: false }
        ListElement { key: "FaceTimeBitRate3G"; checked: false }
        ListElement { key: "FaceTimeBitRateLTE"; checked: false }
        ListElement { key: "FaceTimeBitRateWiFi"; checked: false }
        ListElement { key: "FaceTimeCameraRequiresFastSwitchOptions"; checked: false }
        ListElement { key: "FaceTimeCameraSupportsHardwareFaceDetection"; checked: false }
        ListElement { key: "FaceTimeDecodings"; checked: false }
        ListElement { key: "FaceTimeEncodings"; checked: false }
        ListElement { key: "FaceTimeFrontCameraTemporalNoiseReductionMode"; checked: false }
        ListElement { key: "FaceTimePhotosOptIn"; checked: false }
        ListElement { key: "FaceTimePreferredDecoding"; checked: false }
        ListElement { key: "FaceTimePreferredEncoding"; checked: false }
        ListElement { key: "FirmwareNonce"; checked: false }
        ListElement { key: "FirmwarePreflightInfo"; checked: false }
        ListElement { key: "FirmwareVersion"; checked: false }
        ListElement { key: "FirstPartyLaunchTimeLimitScale"; checked: false }
        ListElement { key: "ForwardCameraCapability"; checked: false }
        ListElement { key: "FrontCameraOffsetFromDisplayCenter"; checked: false }
        ListElement { key: "FrontCameraRotationFromDisplayNormal"; checked: false }
        ListElement { key: "FrontFacingCameraAutoHDRCapability"; checked: false }
        ListElement { key: "FrontFacingCameraBurstCapability"; checked: false }
        ListElement { key: "FrontFacingCameraCapability"; checked: false }
        ListElement { key: "FrontFacingCameraHDRCapability"; checked: false }
        ListElement { key: "FrontFacingCameraHDROnCapability"; checked: false }
        ListElement { key: "FrontFacingCameraHFRCapability"; checked: false }
        ListElement { key: "FrontFacingCameraHFRVideoCapture1080pMaxFPS"; checked: false }
        ListElement { key: "FrontFacingCameraHFRVideoCapture720pMaxFPS"; checked: false }
        ListElement { key: "FrontFacingCameraMaxVideoZoomFactor"; checked: false }
        ListElement { key: "FrontFacingCameraModuleSerialNumber"; checked: false }
        ListElement { key: "FrontFacingCameraStillDurationForBurst"; checked: false }
        ListElement { key: "FrontFacingCameraVideoCapture1080pMaxFPS"; checked: false }
        ListElement { key: "FrontFacingCameraVideoCapture4kMaxFPS"; checked: false }
        ListElement { key: "FrontFacingCameraVideoCapture720pMaxFPS"; checked: false }
        ListElement { key: "FrontFacingIRCameraModuleSerialNumber"; checked: false }
        ListElement { key: "FrontFacingIRStructuredLightProjectorModuleSerialNumber"; checked: false }
        ListElement { key: "Full6FeaturesCapability"; checked: false }
        ListElement { key: "GPSCapability"; checked: false }
        ListElement { key: "GSDeviceName"; checked: false }
        ListElement { key: "GameKitCapability"; checked: false }
        ListElement { key: "GasGaugeBatteryCapability"; checked: false }
        ListElement { key: "GreenTeaDeviceCapability"; checked: false }
        ListElement { key: "GyroscopeCapability"; checked: false }
        ListElement { key: "H264EncoderCapability"; checked: false }
        ListElement { key: "HDRImageCaptureCapability"; checked: false }
        ListElement { key: "HDVideoCaptureCapability"; checked: false }
        ListElement { key: "HEVCDecoder10bitSupported"; checked: false }
        ListElement { key: "HEVCDecoder12bitSupported"; checked: false }
        ListElement { key: "HEVCDecoder8bitSupported"; checked: false }
        ListElement { key: "HEVCEncodingCapability"; checked: false }
        ListElement { key: "HMERefreshRateInARKit"; checked: false }
        ListElement { key: "HWModelStr"; checked: false }
        ListElement { key: "HallEffectSensorCapability"; checked: false }
        ListElement { key: "HardwareEncodeSnapshotsCapability"; checked: false }
        ListElement { key: "HardwareKeyboardCapability"; checked: false }
        ListElement { key: "HardwarePlatform"; checked: false }
        ListElement { key: "HardwareSnapshotsRequirePurpleGfxCapability"; checked: false }
        ListElement { key: "HasAllFeaturesCapability"; checked: false }
        ListElement { key: "HasAppleNeuralEngine"; checked: false }
        ListElement { key: "HasBaseband"; checked: false }
        ListElement { key: "HasBattery"; checked: false }
        ListElement { key: "HasDaliMode"; checked: false }
        ListElement { key: "HasExtendedColorDisplay"; checked: false }
        ListElement { key: "HasIcefall"; checked: false }
        ListElement { key: "HasInternalSettingsBundle"; checked: false }
        ListElement { key: "HasMesa"; checked: false }
        ListElement { key: "HasPKA"; checked: false }
        ListElement { key: "HasSEP"; checked: false }
        ListElement { key: "HasSpringBoard"; checked: false }
        ListElement { key: "HasThinBezel"; checked: false }
        ListElement { key: "HealthKitCapability"; checked: false }
        ListElement { key: "HearingAidAudioEqualizationCapability"; checked: false }
        ListElement { key: "HearingAidLowEnergyAudioCapability"; checked: false }
        ListElement { key: "HearingAidPowerReductionCapability"; checked: false }
        ListElement { key: "HiDPICapability"; checked: false }
        ListElement { key: "HiccoughInterval"; checked: false }
        ListElement { key: "HideNonDefaultApplicationsCapability"; checked: false }
        ListElement { key: "HighestSupportedVideoMode"; checked: false }
        ListElement { key: "HomeButtonType"; checked: false }
        ListElement { key: "HomeScreenWallpaperCapability"; checked: false }
        ListElement { key: "IDAMCapability"; checked: false }
        ListElement { key: "IOSurfaceBackedImagesCapability"; checked: false }
        ListElement { key: "IOSurfaceFormatDictionary"; checked: false }
        ListElement { key: "IceFallID"; checked: false }
        ListElement { key: "IcefallInRestrictedMode"; checked: false }
        ListElement { key: "IcefallInfo"; checked: false }
        ListElement { key: "Image4CryptoHashMethod"; checked: false }
        ListElement { key: "Image4Supported"; checked: false }
        ListElement { key: "InDiagnosticsMode"; checked: false }
        ListElement { key: "IntegratedCircuitCardIdentifier"; checked: false }
        ListElement { key: "IntegratedCircuitCardIdentifier2"; checked: false }
        ListElement { key: "InternalBuild"; checked: false }
        ListElement { key: "InternationalMobileEquipmentIdentity"; checked: false }
        ListElement { key: "InternationalMobileEquipmentIdentity2"; checked: false }
        ListElement { key: "InternationalSettingsCapability"; checked: false }
        ListElement { key: "InverseDeviceID"; checked: false }
        ListElement { key: "IsEmulatedDevice"; checked: false }
        ListElement { key: "IsLargeFormatPhone"; checked: false }
        ListElement { key: "IsPwrOpposedVol"; checked: false }
        ListElement { key: "IsServicePart"; checked: false }
        ListElement { key: "IsSimulator"; checked: false }
        ListElement { key: "IsThereEnoughBatteryLevelForSoftwareUpdate"; checked: false }
        ListElement { key: "IsUIBuild"; checked: false }
        ListElement { key: "JasperSerialNumber"; checked: false }
        ListElement { key: "LTEDeviceCapability"; checked: false }
        ListElement { key: "LaunchTimeLimitScaleSupported"; checked: false }
        ListElement { key: "LisaCapability"; checked: false }
        ListElement { key: "LoadThumbnailsWhileScrollingCapability"; checked: false }
        ListElement { key: "LocalizedDeviceNameString"; checked: false }
        ListElement { key: "LocationRemindersCapability"; checked: false }
        ListElement { key: "LocationServicesCapability"; checked: false }
        ListElement { key: "LowPowerWalletMode"; checked: false }
        ListElement { key: "LunaFlexSerialNumber"; checked: false }
        ListElement { key: "LynxPublicKey"; checked: false }
        ListElement { key: "LynxSerialNumber"; checked: false }
        ListElement { key: "MLBSerialNumber"; checked: false }
        ListElement { key: "MLEHW"; checked: false }
        ListElement { key: "MMSCapability"; checked: false }
        ListElement { key: "MacBridgingKeys"; checked: false }
        ListElement { key: "MagnetometerCapability"; checked: false }
        ListElement { key: "MainDisplayRotation"; checked: false }
        ListElement { key: "MainScreenCanvasSizes"; checked: false }
        ListElement { key: "MainScreenClass"; checked: false }
        ListElement { key: "MainScreenHeight"; checked: false }
        ListElement { key: "MainScreenOrientation"; checked: false }
        ListElement { key: "MainScreenPitch"; checked: false }
        ListElement { key: "MainScreenScale"; checked: false }
        ListElement { key: "MainScreenStaticInfo"; checked: false }
        ListElement { key: "MainScreenWidth"; checked: false }
        ListElement { key: "MarketingNameString"; checked: false }
        ListElement { key: "MarketingProductName"; checked: false }
        ListElement { key: "MarketingVersion"; checked: false }
        ListElement { key: "MaxH264PlaybackLevel"; checked: false }
        ListElement { key: "MaximumScreenScale"; checked: false }
        ListElement { key: "MedusaFloatingLiveAppCapability"; checked: false }
        ListElement { key: "MedusaOverlayAppCapability"; checked: false }
        ListElement { key: "MedusaPIPCapability"; checked: false }
        ListElement { key: "MedusaPinnedAppCapability"; checked: false }
        ListElement { key: "MesaSerialNumber"; checked: false }
        ListElement { key: "MetalCapability"; checked: false }
        ListElement { key: "MicrophoneCapability"; checked: false }
        ListElement { key: "MicrophoneCount"; checked: false }
        ListElement { key: "MinimumSupportediTunesVersion"; checked: false }
        ListElement { key: "MixAndMatchPrevention"; checked: false }
        ListElement { key: "MobileDeviceMinimumVersion"; checked: false }
        ListElement { key: "MobileEquipmentIdentifier"; checked: false }
        ListElement { key: "MobileEquipmentInfoBaseId"; checked: false }
        ListElement { key: "MobileEquipmentInfoBaseProfile"; checked: false }
        ListElement { key: "MobileEquipmentInfoBaseVersion"; checked: false }
        ListElement { key: "MobileEquipmentInfoCSN"; checked: false }
        ListElement { key: "MobileEquipmentInfoDisplayCSN"; checked: false }
        ListElement { key: "MobileSubscriberCountryCode"; checked: false }
        ListElement { key: "MobileSubscriberNetworkCode"; checked: false }
        ListElement { key: "MobileWifi"; checked: false }
        ListElement { key: "ModelNumber"; checked: false }
        ListElement { key: "MonarchLowEndHardware"; checked: false }
        ListElement { key: "MultiLynxPublicKeyArray"; checked: false }
        ListElement { key: "MultiLynxSerialNumberArray"; checked: false }
        ListElement { key: "MultitaskingCapability"; checked: false }
        ListElement { key: "MultitaskingGesturesCapability"; checked: false }
        ListElement { key: "MusicStore"; checked: false }
        ListElement { key: "MusicStoreCapability"; checked: false }
        ListElement { key: "N78aHack"; checked: false }
        ListElement { key: "NFCRadio"; checked: false }
        ListElement { key: "NFCRadioCalibrationDataPresent"; checked: false }
        ListElement { key: "NFCUniqueChipID"; checked: false }
        ListElement { key: "NVRAMDictionary"; checked: false }
        ListElement { key: "NandControllerUID"; checked: false }
        ListElement { key: "NavajoFusingState"; checked: false }
        ListElement { key: "NikeIpodCapability"; checked: false }
        ListElement { key: "NotGreenTeaDeviceCapability"; checked: false }
        ListElement { key: "OLEDDisplay"; checked: false }
        ListElement { key: "OTAActivationCapability"; checked: false }
        ListElement { key: "OfflineDictationCapability"; checked: false }
        ListElement { key: "OpenGLES1Capability"; checked: false }
        ListElement { key: "OpenGLES2Capability"; checked: false }
        ListElement { key: "OpenGLES3Capability"; checked: false }
        ListElement { key: "OpenGLESVersion"; checked: false }
        ListElement { key: "PTPLargeFilesCapability"; checked: false }
        ListElement { key: "PanelSerialNumber"; checked: false }
        ListElement { key: "PanoramaCameraCapability"; checked: false }
        ListElement { key: "PartitionType"; checked: false }
        ListElement { key: "PasswordConfigured"; checked: false }
        ListElement { key: "PasswordProtected"; checked: false }
        ListElement { key: "PearlCameraCapability"; checked: false }
        ListElement { key: "PearlIDCapability"; checked: false }
        ListElement { key: "PeekUICapability"; checked: false }
        ListElement { key: "PeekUIWidth"; checked: false }
        ListElement { key: "Peer2PeerCapability"; checked: false }
        ListElement { key: "PersonalHotspotCapability"; checked: false }
        ListElement { key: "PhoneNumber"; checked: false }
        ListElement { key: "PhoneNumber2"; checked: false }
        ListElement { key: "PhosphorusCapability"; checked: false }
        ListElement { key: "PhotoAdjustmentsCapability"; checked: false }
        ListElement { key: "PhotoCapability"; checked: false }
        ListElement { key: "PhotoSharingCapability"; checked: false }
        ListElement { key: "PhotoStreamCapability"; checked: false }
        ListElement { key: "PhotosPostEffectsCapability"; checked: false }
        ListElement { key: "PiezoClickerCapability"; checked: false }
        ListElement { key: "PintoMacAddress"; checked: false }
        ListElement { key: "PintoMacAddressData"; checked: false }
        ListElement { key: "PipelinedStillImageProcessingCapability"; checked: false }
        ListElement { key: "PlatformStandAloneContactsCapability"; checked: false }
        ListElement { key: "PlatinumCapability"; checked: false }
        ListElement { key: "ProductHash"; checked: false }
        ListElement { key: "ProductName"; checked: false }
        ListElement { key: "ProductType"; checked: false }
        ListElement { key: "ProductVersion"; checked: false }
        ListElement { key: "ProximitySensorCalibration"; checked: false }
        ListElement { key: "ProximitySensorCalibrationDictionary"; checked: false }
        ListElement { key: "ProximitySensorCapability"; checked: false }
        ListElement { key: "RF-exposure-separation-distance"; checked: false }
        ListElement { key: "RFExposureSeparationDistance"; checked: false }
        ListElement { key: "RawPanelSerialNumber"; checked: false }
        ListElement { key: "RearCameraCapability"; checked: false }
        ListElement { key: "RearCameraOffsetFromDisplayCenter"; checked: false }
        ListElement { key: "RearFacingCamera60fpsVideoCaptureCapability"; checked: false }
        ListElement { key: "RearFacingCameraAutoHDRCapability"; checked: false }
        ListElement { key: "RearFacingCameraBurstCapability"; checked: false }
        ListElement { key: "RearFacingCameraCapability"; checked: false }
        ListElement { key: "RearFacingCameraHDRCapability"; checked: false }
        ListElement { key: "RearFacingCameraHDROnCapability"; checked: false }
        ListElement { key: "RearFacingCameraHFRCapability"; checked: false }
        ListElement { key: "RearFacingCameraHFRVideoCapture1080pMaxFPS"; checked: false }
        ListElement { key: "RearFacingCameraHFRVideoCapture720pMaxFPS"; checked: false }
        ListElement { key: "RearFacingCameraMaxVideoZoomFactor"; checked: false }
        ListElement { key: "RearFacingCameraModuleSerialNumber"; checked: false }
        ListElement { key: "RearFacingCameraStillDurationForBurst"; checked: false }
        ListElement { key: "RearFacingCameraSuperWideCameraCapability"; checked: false }
        ListElement { key: "RearFacingCameraTimeOfFlightCameraCapability"; checked: false }
        ListElement { key: "RearFacingCameraVideoCapture1080pMaxFPS"; checked: false }
        ListElement { key: "RearFacingCameraVideoCapture4kMaxFPS"; checked: false }
        ListElement { key: "RearFacingCameraVideoCapture720pMaxFPS"; checked: false }
        ListElement { key: "RearFacingCameraVideoCaptureFPS"; checked: false }
        ListElement { key: "RearFacingLowLightCameraCapability"; checked: false }
        ListElement { key: "RearFacingSuperWideCameraModuleSerialNumber"; checked: false }
        ListElement { key: "RearFacingTelephotoCameraCapability"; checked: false }
        ListElement { key: "RearFacingTelephotoCameraModuleSerialNumber"; checked: false }
        ListElement { key: "RecoveryOSVersion"; checked: false }
        ListElement { key: "RegionCode"; checked: false }
        ListElement { key: "RegionInfo"; checked: false }
        ListElement { key: "RegionSupportsCinnamon"; checked: false }
        ListElement { key: "RegionalBehaviorAll"; checked: false }
        ListElement { key: "RegionalBehaviorChinaBrick"; checked: false }
        ListElement { key: "RegionalBehaviorEUVolumeLimit"; checked: false }
        ListElement { key: "RegionalBehaviorGB18030"; checked: false }
        ListElement { key: "RegionalBehaviorGoogleMail"; checked: false }
        ListElement { key: "RegionalBehaviorNTSC"; checked: false }
        ListElement { key: "RegionalBehaviorNoPasscodeLocationTiles"; checked: false }
        ListElement { key: "RegionalBehaviorNoVOIP"; checked: false }
        ListElement { key: "RegionalBehaviorNoWiFi"; checked: false }
        ListElement { key: "RegionalBehaviorShutterClick"; checked: false }
        ListElement { key: "RegionalBehaviorValid"; checked: false }
        ListElement { key: "RegionalBehaviorVolumeLimit"; checked: false }
        ListElement { key: "RegulatoryModelNumber"; checked: false }
        ListElement { key: "ReleaseType"; checked: false }
        ListElement { key: "RemoteBluetoothAddress"; checked: false }
        ListElement { key: "RemoteBluetoothAddressData"; checked: false }
        ListElement { key: "RenderWideGamutImagesAtDisplayTime"; checked: false }
        ListElement { key: "RendersLetterPressSlowly"; checked: false }
        ListElement { key: "RequiredBatteryLevelForSoftwareUpdate"; checked: false }
        ListElement { key: "RestoreOSBuild"; checked: false }
        ListElement { key: "RestrictedCountryCodes"; checked: false }
        ListElement { key: "RingerSwitchCapability"; checked: false }
        ListElement { key: "RosalineSerialNumber"; checked: false }
        ListElement { key: "RoswellChipID"; checked: false }
        ListElement { key: "RotateToWakeStatus"; checked: false }
        ListElement { key: "SBAllowSensitiveUI"; checked: false }
        ListElement { key: "SBCanForceDebuggingInfo"; checked: false }
        ListElement { key: "SDIOManufacturerTuple"; checked: false }
        ListElement { key: "SDIOProductInfo"; checked: false }
        ListElement { key: "SEInfo"; checked: false }
        ListElement { key: "SEPNonce"; checked: false }
        ListElement { key: "SIMCapability"; checked: false }
        ListElement { key: "SIMPhonebookCapability"; checked: false }
        ListElement { key: "SIMStatus"; checked: false }
        ListElement { key: "SIMStatus2"; checked: false }
        ListElement { key: "SIMTrayStatus"; checked: false }
        ListElement { key: "SIMTrayStatus2"; checked: false }
        ListElement { key: "SMSCapability"; checked: false }
        ListElement { key: "SavageChipID"; checked: false }
        ListElement { key: "SavageInfo"; checked: false }
        ListElement { key: "SavageSerialNumber"; checked: false }
        ListElement { key: "SavageUID"; checked: false }
        ListElement { key: "ScreenDimensions"; checked: false }
        ListElement { key: "ScreenDimensionsCapability"; checked: false }
        ListElement { key: "ScreenRecorderCapability"; checked: false }
        ListElement { key: "ScreenSerialNumber"; checked: false }
        ListElement { key: "SecondaryBluetoothMacAddress"; checked: false }
        ListElement { key: "SecondaryBluetoothMacAddressData"; checked: false }
        ListElement { key: "SecondaryEthernetMacAddress"; checked: false }
        ListElement { key: "SecondaryEthernetMacAddressData"; checked: false }
        ListElement { key: "SecondaryWifiMacAddress"; checked: false }
        ListElement { key: "SecondaryWifiMacAddressData"; checked: false }
        ListElement { key: "SecureElement"; checked: false }
        ListElement { key: "SecureElementID"; checked: false }
        ListElement { key: "SecurityDomain"; checked: false }
        ListElement { key: "SensitiveUICapability"; checked: false }
        ListElement { key: "SerialNumber"; checked: false }
        ListElement { key: "ShoeboxCapability"; checked: false }
        ListElement { key: "ShouldHactivate"; checked: false }
        ListElement { key: "SiKACapability"; checked: false }
        ListElement { key: "SigningFuse"; checked: false }
        ListElement { key: "SiliconBringupBoard"; checked: false }
        ListElement { key: "SimultaneousCallAndDataCurrentlySupported"; checked: false }
        ListElement { key: "SimultaneousCallAndDataSupported"; checked: false }
        ListElement { key: "SiriGestureCapability"; checked: false }
        ListElement { key: "SiriOfflineCapability"; checked: false }
        ListElement { key: "Skey"; checked: false }
        ListElement { key: "SoftwareBehavior"; checked: false }
        ListElement { key: "SoftwareBundleVersion"; checked: false }
        ListElement { key: "SoftwareDimmingAlpha"; checked: false }
        ListElement { key: "SpeakerCalibrationMiGa"; checked: false }
        ListElement { key: "SpeakerCalibrationSpGa"; checked: false }
        ListElement { key: "SpeakerCalibrationSpTS"; checked: false }
        ListElement { key: "SphereCapability"; checked: false }
        ListElement { key: "StarkCapability"; checked: false }
        ListElement { key: "StockholmJcopInfo"; checked: false }
        ListElement { key: "StrictWakeKeyboardCases"; checked: false }
        ListElement { key: "SupportedDeviceFamilies"; checked: false }
        ListElement { key: "SupportedKeyboards"; checked: false }
        ListElement { key: "SupportsBurninMitigation"; checked: false }
        ListElement { key: "SupportsEDUMU"; checked: false }
        ListElement { key: "SupportsForceTouch"; checked: false }
        ListElement { key: "SupportsIrisCapture"; checked: false }
        ListElement { key: "SupportsLowPowerMode"; checked: false }
        ListElement { key: "SupportsPerseus"; checked: false }
        ListElement { key: "SupportsRotateToWake"; checked: false }
        ListElement { key: "SupportsSOS"; checked: false }
        ListElement { key: "SupportsSSHBButtonType"; checked: false }
        ListElement { key: "SupportsTouchRemote"; checked: false }
        ListElement { key: "SysCfg"; checked: false }
        ListElement { key: "SysCfgDict"; checked: false }
        ListElement { key: "SystemImageID"; checked: false }
        ListElement { key: "SystemTelephonyOfAnyKindCapability"; checked: false }
        ListElement { key: "TVOutCrossfadeCapability"; checked: false }
        ListElement { key: "TVOutSettingsCapability"; checked: false }
        ListElement { key: "TelephonyCapability"; checked: false }
        ListElement { key: "TelephonyMaximumGeneration"; checked: false }
        ListElement { key: "TimeSyncCapability"; checked: false }
        ListElement { key: "TopModuleAuthChipID"; checked: false }
        ListElement { key: "TouchDelivery120Hz"; checked: false }
        ListElement { key: "TouchIDCapability"; checked: false }
        ListElement { key: "TristarID"; checked: false }
        ListElement { key: "UIBackgroundQuality"; checked: false }
        ListElement { key: "UIParallaxCapability"; checked: false }
        ListElement { key: "UIProceduralWallpaperCapability"; checked: false }
        ListElement { key: "UIReachability"; checked: false }
        ListElement { key: "UMTSDeviceCapability"; checked: false }
        ListElement { key: "UnifiedIPodCapability"; checked: false }
        ListElement { key: "UniqueChipID"; checked: false }
        ListElement { key: "UniqueDeviceID"; checked: false }
        ListElement { key: "UniqueDeviceIDData"; checked: false }
        ListElement { key: "UserAssignedDeviceName"; checked: false }
        ListElement { key: "UserIntentPhysicalButtonCGRect"; checked: false }
        ListElement { key: "UserIntentPhysicalButtonCGRectString"; checked: false }
        ListElement { key: "UserIntentPhysicalButtonNormalizedCGRect"; checked: false }
        ListElement { key: "VOIPCapability"; checked: false }
        ListElement { key: "VeniceCapability"; checked: false }
        ListElement { key: "VibratorCapability"; checked: false }
        ListElement { key: "VideoCameraCapability"; checked: false }
        ListElement { key: "VideoStillsCapability"; checked: false }
        ListElement { key: "VoiceControlCapability"; checked: false }
        ListElement { key: "VolumeButtonCapability"; checked: false }
        ListElement { key: "WAGraphicQuality"; checked: false }
        ListElement { key: "WAPICapability"; checked: false }
        ListElement { key: "WLANBkgScanCache"; checked: false }
        ListElement { key: "WSKU"; checked: false }
        ListElement { key: "WatchCompanionCapability"; checked: false }
        ListElement { key: "WatchSupportsAutoPlaylistPlayback"; checked: false }
        ListElement { key: "WatchSupportsHighQualityClockFaceGraphics"; checked: false }
        ListElement { key: "WatchSupportsListeningOnGesture"; checked: false }
        ListElement { key: "WatchSupportsMusicStreaming"; checked: false }
        ListElement { key: "WatchSupportsSiriCommute"; checked: false }
        ListElement { key: "WiFiCallingCapability"; checked: false }
        ListElement { key: "WiFiCapability"; checked: false }
        ListElement { key: "WifiAddress"; checked: false }
        ListElement { key: "WifiAddressData"; checked: false }
        ListElement { key: "WifiAntennaSKUVersion"; checked: false }
        ListElement { key: "WifiCallingSecondaryDeviceCapability"; checked: false }
        ListElement { key: "WifiChipset"; checked: false }
        ListElement { key: "WifiFirmwareVersion"; checked: false }
        ListElement { key: "WifiVendor"; checked: false }
        ListElement { key: "WirelessBoardSnum"; checked: false }
        ListElement { key: "WirelessChargingCapability"; checked: false }
        ListElement { key: "YonkersChipID"; checked: false }
        ListElement { key: "YonkersSerialNumber"; checked: false }
        ListElement { key: "YonkersUID"; checked: false }
        ListElement { key: "YouTubeCapability"; checked: false }
        ListElement { key: "YouTubePluginCapability"; checked: false }
        ListElement { key: "accelerometer"; checked: false }
        ListElement { key: "accessibility"; checked: false }
        ListElement { key: "additional-text-tones"; checked: false }
        ListElement { key: "aggregate-cam-photo-zoom"; checked: false }
        ListElement { key: "aggregate-cam-video-zoom"; checked: false }
        ListElement { key: "airDropRestriction"; checked: false }
        ListElement { key: "airplay-mirroring"; checked: false }
        ListElement { key: "airplay-no-mirroring"; checked: false }
        ListElement { key: "all-features"; checked: false }
        ListElement { key: "allow-32bit-apps"; checked: false }
        ListElement { key: "ambient-light-sensor"; checked: false }
        ListElement { key: "ane"; checked: false }
        ListElement { key: "any-telephony"; checked: false }
        ListElement { key: "apn"; checked: false }
        ListElement { key: "apple-internal-install"; checked: false }
        ListElement { key: "applicationInstallation"; checked: false }
        ListElement { key: "arkit"; checked: false }
        ListElement { key: "arm64"; checked: false }
        ListElement { key: "armv6"; checked: false }
        ListElement { key: "armv7"; checked: false }
        ListElement { key: "armv7s"; checked: false }
        ListElement { key: "assistant"; checked: false }
        ListElement { key: "auto-focus"; checked: false }
        ListElement { key: "auto-focus-camera"; checked: false }
        ListElement { key: "baseband-chipset"; checked: false }
        ListElement { key: "bitrate-2g"; checked: false }
        ListElement { key: "bitrate-3g"; checked: false }
        ListElement { key: "bitrate-lte"; checked: false }
        ListElement { key: "bitrate-wifi"; checked: false }
        ListElement { key: "bluetooth"; checked: false }
        ListElement { key: "bluetooth-le"; checked: false }
        ListElement { key: "board-id"; checked: false }
        ListElement { key: "boot-manifest-hash"; checked: false }
        ListElement { key: "boot-nonce"; checked: false }
        ListElement { key: "builtin-mics"; checked: false }
        ListElement { key: "c2k-device"; checked: false }
        ListElement { key: "calibration"; checked: false }
        ListElement { key: "call-forwarding"; checked: false }
        ListElement { key: "call-waiting"; checked: false }
        ListElement { key: "caller-id"; checked: false }
        ListElement { key: "camera-flash"; checked: false }
        ListElement { key: "camera-front"; checked: false }
        ListElement { key: "camera-front-flash"; checked: false }
        ListElement { key: "camera-rear"; checked: false }
        ListElement { key: "cameraRestriction"; checked: false }
        ListElement { key: "car-integration"; checked: false }
        ListElement { key: "cell-broadcast"; checked: false }
        ListElement { key: "cellular-data"; checked: false }
        ListElement { key: "certificate-production-status"; checked: false }
        ListElement { key: "certificate-security-mode"; checked: false }
        ListElement { key: "chip-id"; checked: false }
        ListElement { key: "class"; checked: false }
        ListElement { key: "closed-loop"; checked: false }
        ListElement { key: "config-number"; checked: false }
        ListElement { key: "contains-cellular-radio"; checked: false }
        ListElement { key: "crypto-hash-method"; checked: false }
        ListElement { key: "dali-mode"; checked: false }
        ListElement { key: "data-plan"; checked: false }
        ListElement { key: "debug-board-revision"; checked: false }
        ListElement { key: "delay-sleep-for-headset-click"; checked: false }
        ListElement { key: "device-color-policy"; checked: false }
        ListElement { key: "device-colors"; checked: false }
        ListElement { key: "device-name"; checked: false }
        ListElement { key: "device-name-localized"; checked: false }
        ListElement { key: "dictation"; checked: false }
        ListElement { key: "die-id"; checked: false }
        ListElement { key: "display-mirroring"; checked: false }
        ListElement { key: "display-rotation"; checked: false }
        ListElement { key: "displayport"; checked: false }
        ListElement { key: "does-not-support-gamekit"; checked: false }
        ListElement { key: "effective-production-status"; checked: false }
        ListElement { key: "effective-production-status-ap"; checked: false }
        ListElement { key: "effective-production-status-sep"; checked: false }
        ListElement { key: "effective-security-mode"; checked: false }
        ListElement { key: "effective-security-mode-ap"; checked: false }
        ListElement { key: "effective-security-mode-sep"; checked: false }
        ListElement { key: "enc-top-type"; checked: false }
        ListElement { key: "encode-aac"; checked: false }
        ListElement { key: "encrypted-data-partition"; checked: false }
        ListElement { key: "enforce-googlemail"; checked: false }
        ListElement { key: "enforce-shutter-click"; checked: false }
        ListElement { key: "euicc-chip-id"; checked: false }
        ListElement { key: "explicitContentRestriction"; checked: false }
        ListElement { key: "face-detection-support"; checked: false }
        ListElement { key: "fast-switch-options"; checked: false }
        ListElement { key: "fcc-logos-via-software"; checked: false }
        ListElement { key: "fcm-type"; checked: false }
        ListElement { key: "firmware-version"; checked: false }
        ListElement { key: "flash"; checked: false }
        ListElement { key: "front-auto-hdr"; checked: false }
        ListElement { key: "front-burst"; checked: false }
        ListElement { key: "front-burst-image-duration"; checked: false }
        ListElement { key: "front-facing-camera"; checked: false }
        ListElement { key: "front-flash-capability"; checked: false }
        ListElement { key: "front-hdr"; checked: false }
        ListElement { key: "front-hdr-on"; checked: false }
        ListElement { key: "front-max-video-fps-1080p"; checked: false }
        ListElement { key: "front-max-video-fps-4k"; checked: false }
        ListElement { key: "front-max-video-fps-720p"; checked: false }
        ListElement { key: "front-max-video-zoom"; checked: false }
        ListElement { key: "front-slowmo"; checked: false }
        ListElement { key: "full-6"; checked: false }
        ListElement { key: "function-button_halleffect"; checked: false }
        ListElement { key: "function-button_ringerab"; checked: false }
        ListElement { key: "gamekit"; checked: false }
        ListElement { key: "gas-gauge-battery"; checked: false }
        ListElement { key: "gps"; checked: false }
        ListElement { key: "gps-capable"; checked: false }
        ListElement { key: "green-tea"; checked: false }
        ListElement { key: "gyroscope"; checked: false }
        ListElement { key: "h264-encoder"; checked: false }
        ListElement { key: "hall-effect-sensor"; checked: false }
        ListElement { key: "haptics"; checked: false }
        ListElement { key: "hardware-keyboard"; checked: false }
        ListElement { key: "has-sphere"; checked: false }
        ListElement { key: "hd-video-capture"; checked: false }
        ListElement { key: "hdr-image-capture"; checked: false }
        ListElement { key: "healthkit"; checked: false }
        ListElement { key: "hearingaid-audio-equalization"; checked: false }
        ListElement { key: "hearingaid-low-energy-audio"; checked: false }
        ListElement { key: "hearingaid-power-reduction"; checked: false }
        ListElement { key: "hiccough-interval"; checked: false }
        ListElement { key: "hide-non-default-apps"; checked: false }
        ListElement { key: "hidpi"; checked: false }
        ListElement { key: "home-button-type"; checked: false }
        ListElement { key: "homescreen-wallpaper"; checked: false }
        ListElement { key: "hw-encode-snapshots"; checked: false }
        ListElement { key: "hw-snapshots-need-purplegfx"; checked: false }
        ListElement { key: "iAP2Capability"; checked: false }
        ListElement { key: "iPadCapability"; checked: false }
        ListElement { key: "iTunesFamilyID"; checked: false }
        ListElement { key: "iap2-protocol-supported"; checked: false }
        ListElement { key: "image4-supported"; checked: false }
        ListElement { key: "international-settings"; checked: false }
        ListElement { key: "io-surface-backed-images"; checked: false }
        ListElement { key: "ipad"; checked: false }
        ListElement { key: "kConferenceCallType"; checked: false }
        ListElement { key: "kSimultaneousCallAndDataCurrentlySupported"; checked: false }
        ListElement { key: "kSimultaneousCallAndDataSupported"; checked: false }
        ListElement { key: "large-format-phone"; checked: false }
        ListElement { key: "live-effects"; checked: false }
        ListElement { key: "live-photo-capture"; checked: false }
        ListElement { key: "load-thumbnails-while-scrolling"; checked: false }
        ListElement { key: "location-reminders"; checked: false }
        ListElement { key: "location-services"; checked: false }
        ListElement { key: "low-power-wallet-mode"; checked: false }
        ListElement { key: "lte-device"; checked: false }
        ListElement { key: "magnetometer"; checked: false }
        ListElement { key: "main-screen-class"; checked: false }
        ListElement { key: "main-screen-height"; checked: false }
        ListElement { key: "main-screen-orientation"; checked: false }
        ListElement { key: "main-screen-pitch"; checked: false }
        ListElement { key: "main-screen-scale"; checked: false }
        ListElement { key: "main-screen-width"; checked: false }
        ListElement { key: "marketing-name"; checked: false }
        ListElement { key: "mesa"; checked: false }
        ListElement { key: "metal"; checked: false }
        ListElement { key: "microphone"; checked: false }
        ListElement { key: "mix-n-match-prevention-status"; checked: false }
        ListElement { key: "mms"; checked: false }
        ListElement { key: "modelIdentifier"; checked: false }
        ListElement { key: "multi-touch"; checked: false }
        ListElement { key: "multitasking"; checked: false }
        ListElement { key: "multitasking-gestures"; checked: false }
        ListElement { key: "n78a-mode"; checked: false }
        ListElement { key: "name"; checked: false }
        ListElement { key: "navigation"; checked: false }
        ListElement { key: "nfc"; checked: false }
        ListElement { key: "nfcWithRadio"; checked: false }
        ListElement { key: "nike-ipod"; checked: false }
        ListElement { key: "nike-support"; checked: false }
        ListElement { key: "no-coreroutine"; checked: false }
        ListElement { key: "no-hi-res-buildings"; checked: false }
        ListElement { key: "no-simplistic-road-mesh"; checked: false }
        ListElement { key: "not-green-tea"; checked: false }
        ListElement { key: "offline-dictation"; checked: false }
        ListElement { key: "opal"; checked: false }
        ListElement { key: "opengles-1"; checked: false }
        ListElement { key: "opengles-2"; checked: false }
        ListElement { key: "opengles-3"; checked: false }
        ListElement { key: "opposed-power-vol-buttons"; checked: false }
        ListElement { key: "ota-activation"; checked: false }
        ListElement { key: "panorama"; checked: false }
        ListElement { key: "peek-ui-width"; checked: false }
        ListElement { key: "peer-peer"; checked: false }
        ListElement { key: "personal-hotspot"; checked: false }
        ListElement { key: "photo-adjustments"; checked: false }
        ListElement { key: "photo-stream"; checked: false }
        ListElement { key: "piezo-clicker"; checked: false }
        ListElement { key: "pipelined-stillimage-capability"; checked: false }
        ListElement { key: "platinum"; checked: false }
        ListElement { key: "post-effects"; checked: false }
        ListElement { key: "pressure"; checked: false }
        ListElement { key: "prox-sensor"; checked: false }
        ListElement { key: "proximity-sensor"; checked: false }
        ListElement { key: "ptp-large-files"; checked: false }
        ListElement { key: "public-key-accelerator"; checked: false }
        ListElement { key: "rear-auto-hdr"; checked: false }
        ListElement { key: "rear-burst"; checked: false }
        ListElement { key: "rear-burst-image-duration"; checked: false }
        ListElement { key: "rear-cam-telephoto-capability"; checked: false }
        ListElement { key: "rear-facing-camera"; checked: false }
        ListElement { key: "rear-hdr"; checked: false }
        ListElement { key: "rear-hdr-on"; checked: false }
        ListElement { key: "rear-max-slomo-video-fps-1080p"; checked: false }
        ListElement { key: "rear-max-slomo-video-fps-720p"; checked: false }
        ListElement { key: "rear-max-video-fps-1080p"; checked: false }
        ListElement { key: "rear-max-video-fps-4k"; checked: false }
        ListElement { key: "rear-max-video-fps-720p"; checked: false }
        ListElement { key: "rear-max-video-frame_rate"; checked: false }
        ListElement { key: "rear-max-video-zoom"; checked: false }
        ListElement { key: "rear-slowmo"; checked: false }
        ListElement { key: "regulatory-model-number"; checked: false }
        ListElement { key: "ringer-switch"; checked: false }
        ListElement { key: "role"; checked: false }
        ListElement { key: "s8000"; checked: false }
        ListElement { key: "s8003"; checked: false }
        ListElement { key: "sandman-support"; checked: false }
        ListElement { key: "screen-dimensions"; checked: false }
        ListElement { key: "sensitive-ui"; checked: false }
        ListElement { key: "shoebox"; checked: false }
        ListElement { key: "sika-support"; checked: false }
        ListElement { key: "sim"; checked: false }
        ListElement { key: "sim-phonebook"; checked: false }
        ListElement { key: "siri-gesture"; checked: false }
        ListElement { key: "slow-letterpress-rendering"; checked: false }
        ListElement { key: "sms"; checked: false }
        ListElement { key: "software-bundle-version"; checked: false }
        ListElement { key: "software-dimming-alpha"; checked: false }
        ListElement { key: "stand-alone-contacts"; checked: false }
        ListElement { key: "still-camera"; checked: false }
        ListElement { key: "stockholm"; checked: false }
        ListElement { key: "supports-always-listening"; checked: false }
        ListElement { key: "t7000"; checked: false }
        ListElement { key: "telephony"; checked: false }
        ListElement { key: "telephony-maximum-generation"; checked: false }
        ListElement { key: "thin-bezel"; checked: false }
        ListElement { key: "tnr-mode-back"; checked: false }
        ListElement { key: "tnr-mode-front"; checked: false }
        ListElement { key: "touch-id"; checked: false }
        ListElement { key: "tv-out-crossfade"; checked: false }
        ListElement { key: "tv-out-settings"; checked: false }
        ListElement { key: "ui-background-quality"; checked: false }
        ListElement { key: "ui-no-parallax"; checked: false }
        ListElement { key: "ui-no-procedural-wallpaper"; checked: false }
        ListElement { key: "ui-pip"; checked: false }
        ListElement { key: "ui-reachability"; checked: false }
        ListElement { key: "ui-traffic-cheap-shaders"; checked: false }
        ListElement { key: "ui-weather-quality"; checked: false }
        ListElement { key: "umts-device"; checked: false }
        ListElement { key: "unified-ipod"; checked: false }
        ListElement { key: "unique-chip-id"; checked: false }
        ListElement { key: "venice"; checked: false }
        ListElement { key: "video-camera"; checked: false }
        ListElement { key: "video-cap"; checked: false }
        ListElement { key: "video-stills"; checked: false }
        ListElement { key: "voice-control"; checked: false }
        ListElement { key: "voip"; checked: false }
        ListElement { key: "volume-buttons"; checked: false }
        ListElement { key: "wapi"; checked: false }
        ListElement { key: "watch-companion"; checked: false }
        ListElement { key: "wi-fi"; checked: false }
        ListElement { key: "wifi"; checked: false }
        ListElement { key: "wifi-antenna-sku-info"; checked: false }
        ListElement { key: "wifi-chipset"; checked: false }
        ListElement { key: "wifi-module-sn"; checked: false }
        ListElement { key: "wlan"; checked: false }
        ListElement { key: "wlan.background-scan-cache"; checked: false }
        ListElement { key: "youtube"; checked: false }
        ListElement { key: "youtubePlugin"; checked: false }
    }

}