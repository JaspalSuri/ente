import "package:computer/computer.dart";
import "package:logging/logging.dart";
import "package:onnxruntime/onnxruntime.dart";
import 'package:photos/services/machine_learning/semantic_search/frameworks/ml_framework.dart';
import 'package:photos/services/machine_learning/semantic_search/frameworks/onnx/onnx_image_encoder.dart';
import 'package:photos/services/machine_learning/semantic_search/frameworks/onnx/onnx_text_encoder.dart';
import "package:photos/utils/image_isolate.dart";

class ONNX extends MLFramework {
  static const kModelBucketEndpoint =
      "https://huggingface.co/immich-app/ViT-B-32__openai/resolve/main/";
  static const kImageModel = "visual/model.onnx";
  // static const kTextModel = "clip-text-vit-32-uint8.onnx"; // TODO: check later whether to revert back or not
  static const kTextModel = "textual/model.onnx";

  final _computer = Computer.shared();
  final _logger = Logger("ONNX");
  final _clipImage = OnnxImageEncoder();
  final _clipText = OnnxTextEncoder();
  int _textEncoderAddress = 0;
  int _imageEncoderAddress = 0;

  ONNX(super.shouldDownloadOverMobileData);

  @override
  String getImageModelRemotePath() {
    return kModelBucketEndpoint + kImageModel;
  }

  @override
  String getTextModelRemotePath() {
    return kModelBucketEndpoint + kTextModel;
  }

  @override
  Future<void> init() async {
    await _computer.compute(initOrtEnv);
    await super.init();
  }

  @override
  Future<void> loadImageModel(String path) async {
    final startTime = DateTime.now();
    _imageEncoderAddress = await _computer.compute(
      _clipImage.loadModel,
      param: {
        "imageModelPath": path,
      },
    );
    final endTime = DateTime.now();
    _logger.info(
      "Loading image model took: ${(endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch).toString()}ms",
    );
  }

  @override
  Future<void> loadTextModel(String path) async {
    _logger.info('loadTextModel called');
    final startTime = DateTime.now();
    await _clipText.initTokenizer();
    _textEncoderAddress = await _computer.compute(
      _clipText.loadModel,
      param: {
        "textModelPath": path,
      },
    );
    final endTime = DateTime.now();
    _logger.info(
      "Loading text model took: ${(endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch).toString()}ms",
    );
  }

  @override
  Future<List<double>> getImageEmbedding(String imagePath) async {
    _logger.info('getImageEmbedding called');
    try {
      final startTime = DateTime.now();
      // TODO: properly integrate with other ml later (FaceMlService)
      final result = await ImageIsolate.instance.inferClipImageEmbedding(
        imagePath,
        _imageEncoderAddress,
      );
      final endTime = DateTime.now();
      _logger.info(
        "getImageEmbedding done in ${(endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch)}ms",
      );
      return result;
    } catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }

  @override
  Future<List<double>> getTextEmbedding(String text) async {
    try {
      final startTime = DateTime.now();
      final result = await _computer.compute(
        _clipText.infer,
        param: {
          "text": text,
          "address": _textEncoderAddress,
        },
        taskName: "createTextEmbedding",
      ) as List<double>;
      final endTime = DateTime.now();
      _logger.info(
        "createTextEmbedding took: ${(endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch)}ms",
      );
      return result;
    } catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }

  @override
  Future<void> release() async {
    final session = OrtSession.fromAddress(_textEncoderAddress);
    session.release();
    OrtEnv.instance.release();
    _logger.info('Released');
  }
}

void initOrtEnv() async {
  OrtEnv.instance.init();
}
