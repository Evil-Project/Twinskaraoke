import Foundation
import UIKit

// MARK: - AboutContent

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

// MARK: - AppLogoData

enum AppLogoData {
    static let shared: Data = NSDataAsset(name: "AppLogo")?.data ?? Data()
}

// MARK: - CreditsArtists

enum CreditsArtists {
    static let all: [(String, String)] = [
        ("👽 (owo_uou)", "https://x.com/owo_uou"),
        ("109kpm", "https://space.bilibili.com/626515610"),
        ("5RI", "https://x.com/art5RI"),
        ("Ahche", "https://x.com/Ahchive_Be"),
        ("AlinFaeleas", "https://x.com/alinfaeleas"),
        ("Ame0", "https://x.com/HDaHrBUapT57ndh"),
        ("Amorous艾莫", "https://x.com/AmorousSuc"),
        ("Anima-trix", "https://x.com/animatrix30"),
        ("Aokuma", "https://x.com/aokuma_work"),
        ("AppleC", "https://x.com/AppL_CD"),
        ("Aserus 🐰🪽", "https://x.com/aserusg"),
        ("Asfie", "https://x.com/aesfixcia"),
        ("Astra", "https://x.com/astrachan949"),
        ("Augne", "https://x.com/Panneko_o"),
        ("Ayane Asamura", "https://x.com/l99ayane"),
        ("Bauka", "https://x.com/Baurz1"),
        ("Bitseon", "https://x.com/ksh02178"),
        ("Borzoi", "https://x.com/Deueeuui223"),
        ("CArroT", "https://space.bilibili.com/2038218765"),
        ("catt", "https://x.com/cattocut"),
        ("Chahan🍜", "https://x.com/ChahanRamen2"),
        ("Charismaju", "https://fiverr.com/studartsmaju"),
        ("Clover Dot", "https://x.com/Clov_erD"),
        ("Copper1ion", "https://x.com/Cooper1ion"),
        ("cosmicblubb", "https://x.com/cosmicblubb"),
        ("Dafalgan", "https://x.com/dafalgan09"),
        ("danieax", "https://x.com/DanieaxH"),
        ("DCMeC", "https://www.pixiv.net/users/105368797"),
        ("Diego", "https://x.com/DiegoIsADog_"),
        ("Donzduck", "https://x.com/JackTheFridge"),
        ("Douraze", "https://x.com/DourazeE57303"),
        ("Dreamplanes", "https://x.com/Dreamplanes256"),
        ("E20", "https://x.com/E20_loop"),
        ("eenightlamp", "https://x.com/eenightlamp"),
        ("EOcelot", "https://x.com/EggpieART"),
        ("Erina", "https://x.com/ErinaVtuber"),
        ("Fashae", "https://x.com/Fashaeli"),
        ("FeliXKohai", "https://x.com/FelixKohai"),
        ("fians", "https://x.com/fiansand"),
        ("FieryOnion", "https://x.com/moenaionion"),
        ("floofyjul", "https://linktr.ee/fluffysoraa"),
        ("foame", "https://x.com/foame_"),
        ("Frultea", "https://x.com/frultea_0312"),
        ("Fur31mu", "https://x.com/Fur31mu"),
        ("Gobackgu", "https://x.com/Gobackgu"),
        ("Goyu_Gy", "https://x.com/Goyu_Gy"),
        ("GuRara", "https://x.com/GuRara_31"),
        ("hachio", "https://x.com/hachio81"),
        ("Hanna.S", "https://x.com/HanaShi1821"),
        ("HatKD", "https://x.com/HatKD44"),
        ("heren", "https://x.com/herenjun666"),
        ("hoshistream", "https://x.com/Hoshistream"),
        ("idunno", "https://x.com/dgucedunno"),
        ("Izumi_", "https://x.com/Izumi_IND"),
        ("JIANGDAYU", "https://x.com/JDYDTG123"),
        ("Johnny's Garage", "https://x.com/JohnnyGarageAn"),
        ("K3tchup (tomatojam26)", "https://x.com/s_K3tchup"),
        ("kan", "https://x.com/kan1360"),
        ("kanna", "https://x.com/www88ex"),
        ("kaze", "https://x.com/koishiflandre1"),
        ("KeemunArt", "https://x.com/KeemunArt"),
        ("Key🦋 (soulgluttony)", "https://x.com/soulgluttony"),
        ("kisimaT_T", "https://x.com/kisimaT_T"),
        ("Kitsuneco", "https://x.com/kitsuneco12"),
        ("klef", "https://x.com/k_lef111256"),
        ("klmmox", "https://x.com/klmmox_"),
        ("Korei", "https://x.com/Koreillust"),
        ("KoyoriKei", "https://x.com/koyorikei"),
        ("KyaraShard", "https://x.com/KyaraShard"),
        ("Ladi", "https://x.com/LaaaaaDi_"),
        ("lappland987", "https://space.bilibili.com/588649898"),
        ("lenkyun02", "https://x.com/len_kyun02"),
        ("LEXingXD (lukuwo2333)", "https://x.com/lukuwo2333"),
        ("lightenbee", "https://x.com/lightenbee"),
        ("LILY", "https://x.com/hanabira06"),
        ("linhcoris", "https://x.com/linhcoris"),
        ("Lisa (lisadikaprio)", "https://x.com/LisadiKaprio"),
        ("Lst", "https://x.com/leafthreet"),
        ("LuLuLu", "https://x.com/Lucferz13"),
        ("Lunacy", "https://x.com/lunacy_420"),
        ("Luphine", "https://x.com/laLuphine"),
        ("Lynx", "https://x.com/lynxstellaa"),
        ("lyrly", "https://space.bilibili.com/603688153"),
        ("MaisatRaisat", "https://x.com/MaisatRaisat"),
        ("Mamiodapao_", "https://x.com/Mamiodapao_"),
        ("Mandradox", "https://x.com/mandradox"),
        ("Maruru Maru", "https://x.com/NotMaruMaruru00"),
        ("MaShiTaUU", "https://x.com/MaShiTaUU"),
        ("Miryang", "https://x.com/Miryang__"),
        ("miso", "https://x.com/yakuutgi"),
        ("Moneka", "https://x.com/Monikaphobia"),
        ("mr.fish399", "https://x.com/MrFish399"),
        ("mumuk沐沐", "https://space.bilibili.com/384458639"),
        ("Naham", "https://x.com/N4_H4M"),
        ("NANAKI54", "https://x.com/xiii_underblade"),
        ("Naofaro", "https://x.com/Naofaroo"),
        ("Nenemu🍓💤", "https://x.com/nenemu_55"),
        ("Nira (0nirauwu0)", "https://x.com/FreakyNira"),
        ("Nythlin", "https://x.com/NythlinVT"),
        ("Nyuakel", "https://x.com/nyuakel"),
        ("Olineeria", "https://x.com/olineeria"),
        ("onymki2", "https://x.com/_onymki2"),
        ("ORENJIINEKO", "https://x.com/orenjineko46873"),
        ("Origonz", "https://x.com/Origonz5"),
        ("P3R", "https://x.com/atari_desu"),
        ("paccha!! 🍕💜", "https://x.com/paccha_7"),
        ("Pchan", "https://x.com/pinkpink939"),
        ("petsuOnMars", "https://x.com/supapetsu"),
        ("philovyc_", "https://x.com/Philovyc_"),
        ("Pius", "https://x.com/kapxapius"),
        ("PTITSA QAQ", "https://x.com/PtitsaQAQ"),
        ("Railyx", "https://x.com/raily_x"),
        ("Rain", "https://x.com/Rain_Lambda"),
        ("RAITvisualworks", "https://x.com/RAITvisualworks"),
        ("realms (skyrealplane)", "https://x.com/skyrealplane"),
        ("Reivoon", "https://x.com/Reivooon"),
        ("reyforn", "https://x.com/reyforn_"),
        ("Rikkuchan", "https://x.com/rikkuchan_neru"),
        ("RocketDraft", "https://x.com/OKRocketBoy1"),
        ("Ruciel", "https://x.com/Ruxiyel"),
        ("rukooo", "https://x.com/ruruk_o2"),
        ("Rune", "https://x.com/000Rune000"),
        ("Sachi", "https://x.com/smelly_sachi"),
        ("SamSam", "https://x.com/Samsam_S2S"),
        ("sAvIor", "https://x.com/sAviOr4429"),
        ("Seeleゼーレ", "https://x.com/seelka_"),
        ("sena_ink", "https://bsky.app/profile/sena.ink"),
        ("Serafhin", "https://x.com/Serafhin1"),
        ("ShanderZone92", "https://facebook.com/shandi.hidayat"),
        ("Shinbaru", "https://x.com/_shinbaru"),
        ("shushiOwO", ""),
        ("Sink (sznkyuu_)", "https://x.com/sznkyuu"),
        ("sknh3", "https://x.com/sknhnhnh"),
        ("Slanter0116", "https://x.com/Slanter0116"),
        ("Sleepkms", "https://x.com/sleeprealsleep"),
        ("smillerbee", "https://x.com/smillerber1"),
        ("Sombinyl", "https://x.com/0419SBN"),
        ("Sugarph", "https://x.com/huedgehog"),
        ("Suge7", "https://space.bilibili.com/3546616711612831"),
        ("Sumi", "https://x.com/XHR6rZIxJiF1b1z"),
        ("suprii", "https://pixiv.net/en/users/10518285"),
        ("takeyabunora", "https://x.com/takeyabunora"),
        ("tanhuluu (food)", "https://x.com/tanhuluu"),
        ("Taprieiko", "https://x.com/Taprieiko"),
        ("TDA (tda.xd)", "https://x.com/tdaishomeless"),
        ("terrain", "https://x.com/terrainb52"),
        ("TheFatum", "https://x.com/thefatum0"),
        ("Tigera", "https://x.com/projectTiGER_"),
        ("Troobs", "https://x.com/TroobsART"),
        ("Tsp0615", "https://x.com/Tspchan1"),
        ("Ultimage", "https://x.com/UltimageYujin"),
        ("UsagiChuuu", "https://x.com/UsagiChuuu"),
        ("Void", "https://x.com/VoidSynatic"),
        ("Whiteくん", "https://x.com/White45838787"),
        ("Wimo", "https://x.com/wimowowo"),
        ("WindSketchy", "https://x.com/WindSketchy"),
        ("Wisteria", "https://wisteriavt-art.carrd.co"),
        ("Yaemaru Pie", "https://x.com/yaemaru_pie"),
        ("yumo", "https://x.com/yumo539959"),
        ("Yuuri", "https://x.com/0914yuuri_k"),
        ("Zerudawa", "https://x.com/Zerudawaa"),
        ("Zhafran", "https://x.com/zhafran_hfz"),
        ("Zinkaa", "https://x.com/zinkaaRT"),
        ("あおらいね🐟 (aoraineoekaki)", "https://x.com/aoraineoekaki"),
        ("アスカ (ASUKA10k)", "https://x.com/ASUKA10k"),
        ("いづ (noise__rxx)", "https://x.com/noise__rxx"),
        ("いわし (wawaisi_iwasi)", "https://x.com/wawaisi_iwasi"),
        ("うさみん (usamin)", "https://x.com/usamin1211"),
        ("えれ (erenshu)", "https://x.com/erenshu"),
        ("かむかむ (kamu_422)", "https://x.com/kamu_422"),
        ("キャリン", "https://x.com/_karyln"),
        ("くっしぃ (qussie)", "https://x.com/qussie"),
        ("くまたそ (gi_irst)", "https://x.com/gi_irst"),
        ("しえら (4ella)", "https://x.com/4ella_art"),
        ("すなお (sunao)", "https://x.com/sunao_no2"),
        ("ねこむ (iiii__gogo)", "https://x.com/iiii__gogo"),
        ("ぼちゃ𓃵", "https://x.com/Bocha_2_2"),
        ("ほてら🦋🍒 (HoujiTeaLatte)", "https://x.com/HoujiTeaLatte_"),
        ("みこし (mikoshi)", "https://x.com/mikoshi_illust"),
        ("やなぎ (Yanagi)", "https://x.com/WnjfNvku7lDvMv9"),
        ("ラテ🥛 (satera723)", "https://x.com/satera723"),
        ("乱码奔腾 [LUANMA]", "https://x.com/luanma96"),
        ("二十七度火", "https://space.bilibili.com/278484760"),
        ("六狸木芸窗", "https://space.bilibili.com/24521463/dynamic"),
        ("冰岩荔枝", "https://space.bilibili.com/485117171"),
        ("升由るむ🩵🍄 (Masuyu rumu)", "https://x.com/Masuyu_rumu"),
        ("吉_ヴィーナス", "https://space.bilibili.com/39188322/dynamic"),
        ("坂菜 𓈒𓏸*", "https://x.com/Sakana0610773"),
        ("字榎えの (uenoeno)", "https://x.com/uenoeno_"),
        ("宅笙Zhai_Sheng (ZS_IN_CHINA)", "https://x.com/ZS_IN_CHINA"),
        ("宇宙蹦迪秋莎 (Marisa Una)", "https://space.bilibili.com/11156485"),
        ("小月明酱", "https://space.bilibili.com/91397867"),
        ("山楂 (shanzha114514)", "https://x.com/shanzha114514"),
        ("巳蝰 (Bitis)", "https://space.bilibili.com/381660852"),
        ("忽悠 (kasoke)", "https://x.com/kasoke308"),
        ("成吉柯德1560", "https://space.bilibili.com/295017712"),
        ("日土葉 (hidzuchi)", "https://x.com/hidzuchi_18"),
        ("晓马LLK", "https://x.com/xiaomaCroz"),
        ("曦月_Gigetsu", "https://space.bilibili.com/12390629/dynamic"),
        ("水金属liquain", "https://x.com/liquain_"),
        ("泠喵喵i (lingmiaoi)", "https://x.com/lingmiaoooii"),
        ("炭块UwU", "https://space.bilibili.com/100840024"),
        ("炭烤龙尾巴", "https://space.bilibili.com/2108308"),
        ("瑟林SOREN", "https://x.com/sorenFTT"),
        ("真焕琴 (Neoriaquin)", "https://space.bilibili.com/484703647"),
        ("福沢 (yyy_fukuzawa)", "https://x.com/yyy_fukuzawa"),
        ("約Soku", "https://x.com/yuesoku_"),
        ("結木ユウ (Indigo Blue)", "https://x.com/Indigo_Blue_anp"),
        ("绢索 (Amogha_Pasa)", "https://x.com/Amogha_Pasa"),
        ("耶底底亚908", "https://space.bilibili.com/1774554671"),
        ("能天使--- (Goldenglow__)", "https://space.bilibili.com/367461513"),
        ("虚無のメメイラ (memeira)", "https://x.com/memeiradesuyo"),
        ("豚バラなすのポン酢仕立て (hknk_029)", "https://x.com/hknk_029"),
        ("近藤武枝 (condotakeshi)", "https://x.com/condotakeshi2"),
        ("鋭川する (kawasuru)", "https://x.com/kawasuru"),
        ("阮翊y (Ruan Yi)", "https://space.bilibili.com/1112728201"),
        ("零悠≡ω≡ (lingyou)", "https://x.com/lingyouzzz"),
    ]
}
