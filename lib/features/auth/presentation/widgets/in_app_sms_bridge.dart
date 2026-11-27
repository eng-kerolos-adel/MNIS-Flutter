export 'in_app_sms_bridge_stub.dart'
    if (dart.library.io) 'in_app_sms_bridge_mobile.dart'
    show SmsBridgeException, InAppSmsBridgeController, InAppSmsBridgeHost;
