import 'dart:async';
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: VhsCameraScreen(),
  ));
}

class VhsCameraScreen extends StatefulWidget {
  const VhsCameraScreen({super.key});

  @override
  State<VhsCameraScreen> createState() => _VhsCameraScreenState();
}

class _VhsCameraScreenState extends State<VhsCameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  late Ticker _ticker;
  double _elapsedTime = 0.0;
  bool _isReady = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  int _selectedCameraIndex = 0;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _rgbShift = 0.006;
  double _noiseLevel = 0.12;
  late DateTime _customDate;
  Timer? _recordTimer;
  int _recordSeconds = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _customDate = DateTime(1996, now.month, now.day);
    _initCamera(_selectedCameraIndex);
    _ticker = createTicker((elapsed) {
      setState(() => _elapsedTime = elapsed.inMilliseconds / 1000.0);
    })..start();
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (cameras.isEmpty) return;
    setState(() => _isReady = false);
    await _controller?.dispose();
    final controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
      enableAudio: true,
    );
    _controller = controller;
    await controller.initialize();
    _minZoom = await controller.getMinZoomLevel();
    _maxZoom = await controller.getMaxZoomLevel();
    _currentZoom = _minZoom;
    if (mounted) setState(() => _isReady = true);
  }

  void _flipCamera() {
    if (cameras.length < 2 || _isRecording || _isProcessing) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
    _initCamera(_selectedCameraIndex);
  }

  Future<void> _pickCustomDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2099),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.redAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _customDate) {
      setState(() => _customDate = picked);
    }
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing || _controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) {
      _recordTimer?.cancel();
      final rawVideo = await _controller!.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });
      await _processAndSaveVideo(rawVideo.path);
    } else {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordSeconds++);
      });
    }
  }

  Future<void> _processAndSaveVideo(String inputPath) async {
    final outputPath = '${inputPath}_vhs.mp4';
    final int shiftPx = (_rgbShift * 1000).round().clamp(1, 20);
    final int noiseAmount = (_noiseLevel * 100).round().clamp(5, 50);
    final command =
        '-i "$inputPath" -vf "crop=ih*3/4:ih,rgbashift=rh=-$shiftPx:bh=$shiftPx,noise=alls=$noiseAmount:allf=t+u,eq=saturation=1.2:contrast=1.1" -c:a copy "$outputPath"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      await Gal.putVideo(outputPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fita VHS salva na galeria!')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao processar o vídeo.')),
        );
      }
    }
    if (mounted) setState(() => _isProcessing = false);
  }

  String _formatDuration(int totalSeconds) {
    final min = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final sec = (totalSeconds % 60).toString().padLeft(2, '0');
    return '00:$min:$sec';
  }

  @override
  void dispose() {
    _ticker.dispose();
    _recordTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('dd/MM/yyyy').format(_customDate);
    final formattedTime = DateFormat('HH:mm').format(DateTime.now());
    const vhsTextStyle = TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontFamily: 'VcrOsdMono',
      shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(2, 2))],
    );
    const labelStyle = TextStyle(
      color: Colors.white70,
      fontFamily: 'VcrOsdMono',
      fontSize: 13,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_isReady && _controller != null)
                        ShaderBuilder(
                          assetKey: 'shaders/vhs.frag',
                          (context, shader, child) {
                            return AnimatedSampler(
                              (image, size, canvas) {
                                shader
                                  ..setFloat(0, size.width)
                                  ..setFloat(1, size.height)
                                  ..setFloat(2, _elapsedTime)
                                  ..setFloat(3, _rgbShift)
                                  ..setFloat(4, _noiseLevel)
                                  ..setImageSampler(0, image);
                                canvas.drawRect(
                                  Offset.zero & size,
                                  Paint()..shader = shader,
                                );
                              },
                              child: CameraPreview(_controller!),
                            );
                          },
                        )
                      else
                        const ColoredBox(
                          color: Colors.black,
                          child: Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _isRecording ? 'REC ●' : 'PLAY ►',
                                  style: vhsTextStyle.copyWith(
                                    color: _isRecording ? Colors.redAccent : Colors.white,
                                  ),
                                ),
                                Text(
                                  _isRecording ? _formatDuration(_recordSeconds) : 'SP',
                                  style: vhsTextStyle,
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                GestureDetector(
                                  onTap: _pickCustomDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white24),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('$formattedDate\n$formattedTime', style: vhsTextStyle),
                                  ),
                                ),
                                Text(
                                  '${_currentZoom.toStringAsFixed(1)}X',
                                  style: vhsTextStyle.copyWith(fontSize: 16),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black87,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.redAccent),
                                SizedBox(height: 12),
                                Text('GRAVANDO NA FITA...', style: vhsTextStyle),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFF1E1E1E),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 75, child: Text('ZOOM W-T', style: labelStyle)),
                      Expanded(
                        child: Slider(
                          value: _currentZoom,
                          min: _minZoom,
                          max: _maxZoom > _minZoom ? _maxZoom : _minZoom + 1.0,
                          activeColor: Colors.amberAccent,
                          onChanged: (_isReady && _maxZoom > _minZoom)
                              ? (val) async {
                                  setState(() => _currentZoom = val);
                                  await _controller?.setZoomLevel(val);
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 75, child: Text('COR RGB', style: labelStyle)),
                      Expanded(
                        child: Slider(
                          value: _rgbShift,
                          min: 0.0,
                          max: 0.025,
                          activeColor: Colors.redAccent,
                          onChanged: (val) => setState(() => _rgbShift = val),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 75, child: Text('CHUVISCO', style: labelStyle)),
                      Expanded(
                        child: Slider(
                          value: _noiseLevel,
                          min: 0.0,
                          max: 0.40,
                          activeColor: Colors.redAccent,
                          onChanged: (val) => setState(() => _noiseLevel = val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _pickCustomDate,
                        icon: const Icon(Icons.calendar_today, color: Colors.white70, size: 28),
                      ),
                      GestureDetector(
                        onTap: _toggleRecording,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white54, width: 4),
                          ),
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: _isRecording ? 26 : 52,
                              height: _isRecording ? 26 : 52,
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(_isRecording ? 6 : 30),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _isRecording ? null : _flipCamera,
                        icon: Icon(
                          Icons.cameraswitch,
                          color: _isRecording ? Colors.white24 : Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
