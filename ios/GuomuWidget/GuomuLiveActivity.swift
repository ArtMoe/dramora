import ActivityKit
import SwiftUI
import WidgetKit

struct GuomuActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var kind: String
        var title: String
        var subtitle: String
        var episode: Int
        var totalEpisodes: Int
        var episodeLabel: String
        var detail: String
        var progress: Double
        var coverBase64: String
        var deepLink: String
    }

    var activityKey: String
}

private struct ActivityData {
    let state: GuomuActivityAttributes.ContentState

    init(context: ActivityViewContext<GuomuActivityAttributes>) {
        state = context.state
    }

    var safeDeepLink: URL {
        URL(string: state.deepLink) ?? URL(string: "guomu://")!
    }

    var coverImage: UIImage? {
        guard !state.coverBase64.isEmpty,
              let data = Data(base64Encoded: state.coverBase64) else {
            return nil
        }
        return UIImage(data: data)
    }

    var progress: Double {
        state.progress.isFinite ? min(max(state.progress, 0), 1) : 0
    }

    var isDownload: Bool { state.kind == "download" }
    var eyebrow: String { isDownload ? "果幕离线缓存" : "果幕短剧" }
    var actionTitle: String { isDownload ? "查看缓存" : "继续播放" }
}

private struct CoverView: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.orange.opacity(0.88), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
    }
}

@main
struct GuomuWidgetBundle: WidgetBundle {
    var body: some Widget {
        GuomuLiveActivityWidget()
    }
}

@available(iOSApplicationExtension 16.1, *)
struct GuomuLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuomuActivityAttributes.self) { context in
            let data = ActivityData(context: context)
            HStack(spacing: 12) {
                CoverView(image: data.coverImage)
                    .frame(width: 50, height: 66)
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.eyebrow)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(data.state.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(data.state.episodeLabel) · \(data.state.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: data.progress)
                        .tint(.orange)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Link(destination: data.safeDeepLink) {
                    Text(data.actionTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.orange, in: Capsule())
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.94))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let data = ActivityData(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CoverView(image: data.coverImage)
                        .frame(width: 46, height: 62)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(data.state.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(data.state.episodeLabel) · \(data.state.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: data.safeDeepLink) {
                        Text(data.actionTitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.orange, in: Capsule())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: data.progress)
                        .tint(.orange)
                }
            } compactLeading: {
                CoverView(image: data.coverImage)
                    .frame(width: 24, height: 30)
            } compactTrailing: {
                ProgressView(value: data.progress)
                    .progressViewStyle(.circular)
                    .tint(.orange)
                    .frame(width: 24, height: 24)
            } minimal: {
                CoverView(image: data.coverImage)
                    .frame(width: 22, height: 26)
            }
            .keylineTint(.orange)
        }
    }
}
