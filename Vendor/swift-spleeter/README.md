# Spleeter local compatibility patch

Based on jiyimeta/swift-spleeter 0.2.0, under the included MIT license.
Source: https://github.com/jiyimeta/swift-spleeter/tree/0.2.0

The app uses structured `separateFile` processing so cancellation cannot outlive
its output directory. On iOS 27, model inference and tensor operations use CPU
execution: background audio does not authorize GPU/Neural Engine inference.
This trades separation speed for a supported foreground/background policy.
