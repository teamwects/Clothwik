import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class WebviewScreen extends StatefulWidget {
  const WebviewScreen({super.key});

  @override
  State<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends State<WebviewScreen> {
  InAppWebViewController? webViewController;
  PullToRefreshController? refreshController;
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  final String homeUrl = "https://clothwik.shop/";
  bool isOffline = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _checkConnectivity();
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    refreshController = PullToRefreshController(
      onRefresh: () {
        if (!isOffline) {
          webViewController?.reload();
        } else {
          refreshController?.endRefreshing();
        }
      },
      options: PullToRefreshOptions(color: Colors.blue),
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF972761),
      statusBarIconBrightness: Brightness.light,
    ));
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
  }

  Future<bool> _hasActiveInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _checkConnectivity() async {
    _connectionStatus = await _connectivity.checkConnectivity();
    bool hasInternet = await _hasActiveInternet();

    if (_connectionStatus == ConnectivityResult.none || !hasInternet) {
      setState(() {
        isOffline = true;
      });
    } else {
      setState(() {
        isOffline = false;
      });
    }
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    _connectionStatus = result;

    bool hasInternet = await _hasActiveInternet();
    setState(() {
      isOffline = result == ConnectivityResult.none || !hasInternet;
    });

    if (!isOffline) {
      webViewController?.reload();
    }
  }

  Future<bool> _showExitConfirmationDialog(BuildContext context) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit'),
        content: const Text('Do you want to exit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final controller = webViewController;
        if (controller != null && await controller.canGoBack()) {
          controller.goBack();
          return false;
        }
        return await _showExitConfirmationDialog(context);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0, // Hides the toolbar
        ),
        body: SafeArea(
          child: isOffline ? _buildOfflinePage() : _buildWebView(),
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      onLoadStop: (controller, url) {
        refreshController?.endRefreshing();
      },
      pullToRefreshController: refreshController,
      onWebViewCreated: (controller) {
        webViewController = controller;
      },
      initialUrlRequest: URLRequest(url: Uri.parse(homeUrl)),
      initialOptions: InAppWebViewGroupOptions(
        crossPlatform: InAppWebViewOptions(
          javaScriptEnabled: true,
          useShouldOverrideUrlLoading: true,
          supportZoom: false,
        ),
        android: AndroidInAppWebViewOptions(
          useHybridComposition: true,
        ),
      ),
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        var uri = navigationAction.request.url;

        if (uri != null) {
          if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationActionPolicy.CANCEL;
            }
          } else if (uri.host.contains("clothwik.shop")) {
            return NavigationActionPolicy.ALLOW;
          } else {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationActionPolicy.CANCEL;
            }
          }
        }

        return NavigationActionPolicy.ALLOW;
      },

      androidOnPermissionRequest: (controller, origin, resources) async {
        return PermissionRequestResponse(
          resources: resources,
          action: PermissionRequestResponseAction.GRANT,
        );
      },
      androidOnGeolocationPermissionsShowPrompt: (InAppWebViewController controller, String origin) async {
        return GeolocationPermissionShowPromptResponse(
          origin: origin, allow: true, retain: true,
        );
      },
      onConsoleMessage: (controller, consoleMessage) {
        print(consoleMessage);
      },
      onDownloadStartRequest: (controller, url) async {
        await downloadFile(url.url.toString());
      },
      onLoadError: (controller, url, code, message) {
        setState(() {
          isOffline = true;
        });
        print('Error loading URL: $message');
      },
      onLoadHttpError: (controller, url, statusCode, description) {
        setState(() {
          isOffline = true;
        });
        print('HTTP error loading URL: $description');
      },
    );
  }

  Widget _buildOfflinePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 100, color: Colors.grey),
          SizedBox(height: 20),
          Text(
            'You are offline',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Text(
            'Please check your internet connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          SizedBox(height: 30),
          ElevatedButton(
            onPressed: () async {
              await _checkConnectivity();
              if (!isOffline) {
                webViewController?.reload();
              }
            },
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> downloadFile(String url) async {
    try {
      var response = await HttpClient().getUrl(Uri.parse(url));
      var fileName = url.split('/').last;
      var bytes = await response.close().then((response) => response.toList());
      var dir = await getExternalStorageDirectory();
      var filePath = '${dir?.path}/$fileName';

      File file = File(filePath);
      await file.writeAsBytes(bytes.expand((element) => element).toList());

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Downloaded to $filePath'),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to download file: $e'),
      ));
    }
  }
}
