import Foundation

enum AboutContent {
    static let intro = """
    Neuro & Evil Karaoke Web Player is a fan-made project created by Soul. \
    It is a community platform dedicated to preserving and enjoying songs covered \
    by Neuro and Evil, along with related fan content.
    """

    static let unofficialNotice =
        "This website is unofficial and is not affiliated with any official Vedal AI entities."

    struct FeatureGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let bullets: [String]
    }

    static let musicFeatures: [FeatureGroup] = [
        FeatureGroup(
            id: "karaoke-songs",
            title: "Songs",
            subtitle: "The core collection of Neuro and Evil covers.",
            systemImage: "music.note.list",
            bullets: [
                "Listen to available songs from the collection.",
                "Create playlists with or without logging in.",
                "Select custom cover art for playlists.",
                "Download songs for personal, non-commercial use.",
                "Create public playlists that other users can view and listen to.",
            ]
        ),
        FeatureGroup(
            id: "radio",
            title: "Neuro 21 Radio Station",
            subtitle: "A 24/7 stream of Neuro and Evil covers.",
            systemImage: "dot.radiowaves.left.and.right",
            bullets: [
                "Broadcasts continuously through the dedicated internet radio station.",
                "Powered by AzuraCast.",
                "Available in the app through the Radio tab.",
            ]
        ),
        FeatureGroup(
            id: "offline",
            title: "Offline Downloads & PWA",
            subtitle: "Ways to keep music available after the first visit.",
            systemImage: "arrow.down.circle.fill",
            bullets: [
                "The website is a Progressive Web App with offline capabilities.",
                "Downloaded songs can be played from browser storage without an internet connection.",
                "This native app stores downloaded audio on this device for offline playback.",
            ]
        ),
    ]

    static let communityFeatures: [FeatureGroup] = [
        FeatureGroup(
            id: "art-gallery",
            title: "Art Gallery",
            subtitle: "Fan-created artwork with explicit artist permission.",
            systemImage: "photo.on.rectangle.angled",
            bullets: [
                "Artwork is displayed for viewing and fan appreciation only.",
                "Artwork may not be reused, redistributed, or commercially exploited without the artist's permission.",
                "Artist credits are provided where applicable.",
                "The revamped tagging system includes over 3,000 tags for granular discovery.",
            ]
        ),
        FeatureGroup(
            id: "video-gallery",
            title: "Video Gallery",
            subtitle: "Clips from streams.",
            systemImage: "play.rectangle.fill",
            bullets: [
                "Videos are edited and uploaded by FlashFire8.",
                "Channel: youtube.com/@neurokaraoke.",
            ]
        ),
        FeatureGroup(
            id: "soundbites",
            title: "Soundbites",
            subtitle: "Short moments captured from streams.",
            systemImage: "waveform",
            bullets: [
                "Features Neuro and Evil soundbites captured from streams.",
                "Created and edited by Rachinova and CJ.",
            ]
        ),
        FeatureGroup(
            id: "quotes",
            title: "Neuro & Evil Quotes",
            subtitle: "Community-submitted memorable lines.",
            systemImage: "quote.bubble.fill",
            bullets: [
                "Submit favorite Neuro and Evil quotes.",
                "Submitters are credited.",
                "Quotes are managed by Promote.",
            ]
        ),
        FeatureGroup(
            id: "canvas",
            title: "Neuro-sama's Swarm Canvas",
            subtitle: "A community canvas project connected to the website.",
            systemImage: "rectangle.and.pencil.and.ellipsis",
            bullets: [
                "Creates pixel art of Neuro-sama and Evil Neuro.",
                "Converts pixel art into canvas-compatible formats.",
                "Coordinates artwork placement on pixel-based game canvases.",
                "pxls.space login sessions persist across page reloads when third-party cookies are available. iOS is not supported.",
                "Contact _laku. on Discord or any Swarm Canvas council member for assistance.",
            ]
        ),
    ]

    static let playFeatures: [FeatureGroup] = [
        FeatureGroup(
            id: "quiz",
            title: "Music Quiz",
            subtitle: "Knowledge games for Neuro and Evil covers.",
            systemImage: "questionmark.circle.fill",
            bullets: [
                "Daily Bandle Challenge with daily, weekly, monthly, and all-time leaderboards.",
                "Practice Mode with customizable rounds and difficulty.",
                "Multiplayer Mode for real-time quiz battles with friends.",
                "Battle Royale eliminates players each round with escalating audio effects and shrinking timers.",
            ]
        ),
        FeatureGroup(
            id: "listen-along",
            title: "Listen Along",
            subtitle: "Synchronized rooms for shared listening.",
            systemImage: "person.2.wave.2.fill",
            bullets: [
                "Create rooms with friends and listen together in real time.",
                "Playback stays synchronized for everyone in the room.",
                "Built-in chat keeps discussion beside the music.",
            ]
        ),
        FeatureGroup(
            id: "chat",
            title: "Real-Time Chat",
            subtitle: "Conversation for rooms and quiz games.",
            systemImage: "bubble.left.and.bubble.right.fill",
            bullets: [
                "Chat with other users in Listen Along rooms.",
                "Chat is also available during multiplayer and battle royale quiz games.",
                "NeuroCop and EvilCop moderate as AI-powered roleplay moderator bots.",
            ]
        ),
        FeatureGroup(
            id: "badges",
            title: "Badges & Leveling",
            subtitle: "Progression across listening and community activities.",
            systemImage: "rosette",
            bullets: [
                "Collect badges by completing activities and achievements.",
                "Earn XP through listening, quizzes, upvoting, and more.",
                "Badges come in Common, Rare, Epic, and Legendary rarities.",
                "Badge art by liquain. Badge art editing by Emuz.",
            ]
        ),
        FeatureGroup(
            id: "currencies",
            title: "Currencies",
            subtitle: "Neuro Coin, Evil Coin, and Twins Coin.",
            systemImage: "circle.hexagongrid.fill",
            bullets: [
                "Coins are earned through listening, daily challenges, quiz games, upvoting, and leveling up.",
                "Each coin is earned on its respective domain.",
                "Coins will be spendable on playlist and upload limit expansion.",
                "Coming soon.",
            ]
        ),
    ]

    static let appFeatures: [FeatureGroup] = [
        FeatureGroup(
            id: "karaoke-app",
            title: "Companion App",
            subtitle: "Community-maintained desktop, Android, and Apple clients.",
            systemImage: "apps.iphone",
            bullets: [
                "Created and maintained by Aferil.",
                "Desktop versions are packaged for Windows, Linux, and macOS.",
                "The Android version is distributed as an APK.",
                "This repository provides the native SwiftUI iPhone, iPad, and Apple Watch app.",
            ]
        ),
    ]

    struct LegalSection: Identifiable {
        let id: String
        let title: String
        let body: String?
        let bullets: [String]

        init(id: String, title: String, body: String? = nil, bullets: [String]) {
            self.id = id
            self.title = title
            self.body = body
            self.bullets = bullets
        }
    }

    static let privacySummary =
        "We collect only the minimal data required to make playback, accounts, playlists, and downloads work."

    static let privacySections: [LegalSection] = [
        LegalSection(
            id: "guest-users",
            title: "Guest Users",
            bullets: [
                "An anonymous guest ID may be stored locally and sent to the API when you browse the catalog.",
                "Guest playlists are tied to that anonymous identifier.",
            ]
        ),
        LegalSection(
            id: "signed-in-users",
            title: "Signed-In Users",
            bullets: [
                "Discord user ID and avatar can be stored when you sign in.",
                "The app stores your sign-in token on this device.",
                "Account tokens are sent to the API to fetch favorites and personal settings.",
            ]
        ),
        LegalSection(
            id: "playlists-uploads",
            title: "Playlists & Uploads",
            bullets: [
                "Playlists are stored securely by the service.",
                "User-uploaded songs remain private unless the service explicitly marks them otherwise.",
                "Public playlists can be viewed and listened to by other users.",
            ]
        ),
        LegalSection(
            id: "device-storage",
            title: "On This Device",
            bullets: [
                "Twinskaraoke stores recently played playlists.",
                "Downloaded audio is stored locally for offline playback.",
                "Cached images, lyrics, and music can be cleared from app settings.",
            ]
        ),
        LegalSection(
            id: "network-services",
            title: "Network Services",
            bullets: [
                "Catalog and account requests are sent to api.neurokaraoke.com.",
                "Audio cover art and song files are streamed from neurokaraoke.com or the configured regional storage host.",
                "Live radio metadata comes from radio.twinskaraoke.com.",
            ]
        ),
        LegalSection(
            id: "not-collected",
            title: "Not Collected",
            body: "We do not sell or share your listening data with third parties.",
            bullets: [
                "Email addresses.",
                "Real names.",
                "Sensitive personal data.",
            ]
        ),
    ]

    static let termsSummary =
        "By using the Neuro & Evil Karaoke Web Player and this client, you agree to these community-use terms."

    static let termsSections: [LegalSection] = [
        LegalSection(
            id: "fan-made",
            title: "Fan-Made Project Disclaimer",
            bullets: [
                "This is a non-commercial, fan-made project.",
                "It is not officially affiliated with Neuro, Evil, Vedal AI, or related official entities.",
            ]
        ),
        LegalSection(
            id: "personal-use",
            title: "Personal & Non-Commercial Use",
            bullets: [
                "All content is provided for personal enjoyment only.",
                "Commercial use is prohibited.",
            ]
        ),
        LegalSection(
            id: "user-responsibility",
            title: "User Responsibility",
            bullets: [
                "Users are solely responsible for any content they upload.",
                "Do not upload content you do not have permission to use.",
            ]
        ),
        LegalSection(
            id: "playlist-retention",
            title: "Playlist Retention",
            bullets: [
                "Guest playlists may be deleted after 30 days of inactivity.",
                "Logged-in users retain playlists across devices.",
            ]
        ),
        LegalSection(
            id: "public-visibility",
            title: "Public Visibility",
            bullets: [
                "Public playlists may be viewed and listened to by other users.",
                "Only make playlists public when the title, artwork, and song selection are appropriate for public browsing.",
            ]
        ),
        LegalSection(
            id: "no-liability",
            title: "No Liability",
            bullets: [
                "The website and app are provided as-is.",
                "The project is not responsible for data loss, service availability, or third-party claims.",
            ]
        ),
        LegalSection(
            id: "copyright",
            title: "Copyright Compliance",
            bullets: [
                "The project complies with DMCA and applicable international copyright regulations.",
                "For credit corrections or take-down requests, use the contact page.",
            ]
        ),
    ]
}
