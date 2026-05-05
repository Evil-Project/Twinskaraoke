import SDWebImageSwiftUI
import SwiftUI

struct AboutView: View {
  private var appVersion: String {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(v) (\(b))"
  }
  var body: some View {
    List {
      Section {
        VStack(spacing: 14) {
          appIconView
          Text("Twinskaraoke")
            .font(.title2.bold())
          Text("Version \(appVersion)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("NEUROKARAOKE.COM • EVILKARAOKE.COM • TWINSKARAOKE.COM")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
        .listRowInsets(.init())
      }
      Section("About Neuro & Evil Karaoke Web Player") {
        Text(aboutIntro)
          .font(.system(size: 14))
          .foregroundStyle(.primary)
          .padding(.vertical, 4)
        Text(unofficialNotice)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .padding(.vertical, 4)
      }
      Section("Explore") {
        NavigationLink {
          longText("Features & Content", body: featuresBody)
        } label: {
          AboutLinkRow(icon: "sparkles", color: .appAccent, title: "Features & Content")
        }
        NavigationLink {
          CreditsView()
        } label: {
          AboutLinkRow(icon: "heart.fill", color: .pink, title: "Credits")
        }
        NavigationLink {
          longText("Language Support", body: languageBody)
        } label: {
          AboutLinkRow(icon: "globe", color: .blue, title: "Language Support")
        }
        NavigationLink {
          iOSAppDevelopmentView()
        } label: {
          AboutLinkRow(icon: "hammer.fill", color: .orange, title: "iOS App Development")
        }
        NavigationLink {
          longText("Contact & Take-Down Requests", body: contactBody)
        } label: {
          AboutLinkRow(icon: "envelope.fill", color: .indigo, title: "Contact")
        }
      }
      Section("Resources") {
        Link(destination: URL(string: "https://radio.twinskaraoke.com")!) {
          AboutLinkRow(
            icon: "dot.radiowaves.left.and.right", color: .appAccent,
            title: "Neuro 21 Radio Station")
        }
        Link(destination: URL(string: "https://api.neurokaraoke.com")!) {
          AboutLinkRow(icon: "server.rack", color: .blue, title: "API Service")
        }
        Link(destination: URL(string: "https://www.youtube.com/@neurokaraoke")!) {
          AboutLinkRow(icon: "play.rectangle.fill", color: .appAccent, title: "Video Gallery (YouTube)")
        }
        Link(destination: URL(string: "https://github.com/Evil-Project/Twinskaraoke")!) {
          AboutLinkRow(
            icon: "chevron.left.forwardslash.chevron.right", color: .black,
            title: "iOS App Source (GitHub)")
        }
      }
      Section("Legal") {
        NavigationLink {
          longText("Privacy Policy", body: privacyBody)
        } label: {
          AboutLinkRow(icon: "hand.raised.fill", color: .gray, title: "Privacy Policy")
        }
        NavigationLink {
          longText("Terms of Service", body: termsBody)
        } label: {
          AboutLinkRow(icon: "doc.text.fill", color: .gray, title: "Terms of Service")
        }
        NavigationLink {
          AcknowledgementsView()
        } label: {
          AboutLinkRow(icon: "shippingbox.fill", color: .orange, title: "Open Source Licenses")
        }
      }
      Section {
        Text("© 2026 Neuro & Evil Karaoke Web Player\nFan-made by Soul. Unofficial.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
          .listRowBackground(Color.clear)
      }
    }
    .navigationTitle("About")
    .navigationBarTitleDisplayMode(.inline)
  }
  private func longText(_ title: String, body: String) -> some View {
    ScrollView {
      LinkifiedText(text: body)
        .font(.system(size: 14))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
  @ViewBuilder
  private var appIconView: some View {
    AnimatedImage(data: NSDataAsset(name: "AppLogo")?.data ?? Data())
      .resizable()
      .scaledToFill()
      .frame(width: 96, height: 96)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
  }
  private static func loadAppIcon() -> UIImage? {
    if let ui = UIImage(named: "AppIcon"), ui.cgImage != nil { return ui }
    if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
      let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
      let files = primary["CFBundleIconFiles"] as? [String],
      let last = files.last,
      let ui = UIImage(named: last),
      ui.cgImage != nil
    {
      return ui
    }
    return nil
  }
  private var aboutIntro: String {
    """
    Neuro & Evil Karaoke Web Player is a fan-made project created by Soul. \
    It is a community platform dedicated to preserving and enjoying songs covered \
    by Neuro and Evil, along with related fan content.
    """
  }
  private var unofficialNotice: String {
    "This website is unofficial and is not affiliated with any official Vedal AI entities."
  }
  private var featuresBody: String {
    """
    KARAOKE SONGS
    • Listen to available songs from the collection
    • Create playlists with or without logging in
    • Select custom cover art for playlists
    • Download songs for personal, non-commercial use
    • Create public playlists that other users can view and listen to
    ART GALLERY
    • Fan-created artwork of Neuro and Evil
    • All artworks displayed are used with explicit permission from the respective artists
    • Artwork may be displayed for viewing and fan appreciation only. Artwork is not to be reused, redistributed, or commercially exploited without the artist's permission
    • Artist credits are provided where applicable
    • Updated with a revamped tagging system featuring over 3,000 tags for more granular artwork search and discovery
    VIDEO GALLERY
    • A gallery of karaoke clips from karaoke streams
    • All videos are edited and uploaded by FlashFire8
    • Channel: youtube.com/@neurokaraoke
    SOUNDBITES
    • A collection of soundbites featuring Neuro and Evil captured from streams
    • Created and edited by Rachinova and CJ
    KARAOKE QUIZ
    Test your knowledge of Neuro and Evil karaoke covers:
    • Daily Bandle Challenge — A new song challenge every day. Daily, weekly, monthly, and all-time leaderboards
    • Practice Mode — Customizable round and difficulty settings
    • Multiplayer Mode — Real-time quiz battles with friends
    • Battle Royale — Last neuron standing! Players are eliminated each round with escalating audio effects and shrinking timers
    LISTEN ALONG
    • Establish rooms with friends and listen to peak music together in real time
    • Synchronized playback so everyone hears the same song at the same time
    • Built-in chat to discuss songs and vibe with the community
    RADIO STATION — NEURO 21 STATION
    A dedicated radio broadcasting all Neuro and Evil karaoke covers 24/7. \
    Powered by AzuraCast, this is an actual internet radio station that streams continuously.
    OFFLINE DOWNLOADS & PWA
    • The website is a Progressive Web App (PWA) with offline capabilities
    • Download songs to your browser storage and listen without an internet connection
    • The site itself is accessible offline after your first visit with internet
    NEURO & EVIL QUOTES
    • Memorable quotes from our esteemed AI overlords
    • Submit your favorite Neuro and Evil quotes — submitters are credited
    • Quotes are managed by Promote
    REAL-TIME CHAT
    • Chat with other users in Listen Along rooms and during multiplayer/battle royale quiz games
    • Moderated by NeuroCop and EvilCop — AI-powered moderator bots roleplaying as Neuro and Evil to keep things fun and safe
    BADGE & LEVELING SYSTEM
    • Collect badges by completing various activities and achievements
    • Earn experience points (XP) through listening, playing quizzes, upvoting, and more to level up your profile
    • Badges come in four rarities: Common, Rare, Epic, and Legendary
    • Badge art by liquain (x.com/liquain_) • Badge art editing by Emuz (x.com/possiblyemuz)
    CURRENCIES — Neuro Coin | Evil Coin | Twins Coin
    • Three in-site currencies earned through activities like listening, playing the daily challenge, quiz games, upvoting, and leveling up
    • Each coin can only be earned on its respective domain (Neuro Coin on neurokaraoke.com, Evil Coin on evilkaraoke.com, Twins Coin on twinskaraoke.com)
    • Spend coins to expand your playlist limit or upload song limit
    • Coming soon!
    KARAOKE APP
    The Neuro & Evil Karaoke App is a community project created and maintained by Aferil. \
    Desktop (Windows), Linux, and macOS versions are packaged as standalone apps. \
    The Android version is available as an APK.
    NEURO-SAMA'S SWARM CANVAS
    A community canvas project connected to the website. Dedicated to:
    • Creating pixel art of Neuro-sama and Evil Neuro
    • Converting pixel art into canvas-compatible formats
    • Coordinating placement of artwork on pixel-based game canvases
    • Login sessions with pxls.space now persist across page reloads (requires third-party cookies; iOS not supported)
    • Contact _laku. on Discord or any Swarm Canvas council members for assistance
    """
  }
  private var languageBody: String {
    """
    The site supports three languages: English, Japanese, and Chinese.
    Hover over or click the language icon in the navigation bar to switch languages.
    """
  }
  private var contactBody: String {
    """
    For inquiries, credit corrections, or copyright take-down requests, please contact:
    @soul1419 on Discord
    """
  }
  private var privacyBody: String {
    """
    PRIVACY
    We collect only minimal data required for functionality.
    Guest users:
    • Anonymous guest ID stored in browser local storage
    Logged-in users:
    • Discord user ID and avatar
    Playlists & uploads:
    • Stored securely
    • User-uploaded songs remain private
    We do not collect emails, real names, or sensitive personal data.
    On this device, Twinskaraoke stores your sign-in token, recently played \
    playlists, and downloaded audio. We do not sell or share your listening \
    data with third parties.
    Anonymous guest identifiers are sent to api.neurokaraoke.com when you browse \
    the catalog. When you sign in, your account token is sent to the same service \
    to fetch your favorites and personal settings. Audio cover art and song files \
    are streamed from neurokaraoke.com. Live radio metadata comes from \
    radio.twinskaraoke.com.
    """
  }
  private var termsBody: String {
    """
    TERMS OF SERVICE
    By using this website, you agree to the following:
    FAN-MADE PROJECT DISCLAIMER
    This website is a non-commercial, fan-made project and is not officially \
    affiliated with Neuro or Evil.
    PERSONAL & NON-COMMERCIAL USE ONLY
    All content is provided for personal enjoyment only. Commercial use is prohibited.
    USER RESPONSIBILITY
    Users are solely responsible for any content they upload.
    PLAYLIST RETENTION POLICY
    Guest playlists may be deleted after 30 days of inactivity. Logged-in users \
    retain playlists across devices.
    PUBLIC VISIBILITY
    Public playlists may be viewed and listened to by other users.
    NO LIABILITY
    The website is provided "as-is". We are not responsible for data loss, \
    service availability, or third-party claims.
    COPYRIGHT COMPLIANCE
    We comply with DMCA and applicable international copyright regulations.
    """
  }
}

private struct AboutLinkRow: View {
  let icon: String
  let color: Color
  let title: String
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      Text(title)
      Spacer()
    }
  }
}

private struct CreditsView: View {
  var body: some View {
    List {
      Section("Site Creation & Management") {
        creditRow(name: "Soul", detail: "Creator & Developer")
      }
      Section("Banner & Branding") {
        creditRow(name: "Fians", detail: "Website banner art", url: "https://x.com/fiansand")
        creditRow(name: "Promote", detail: "Banner editing")
        creditRow(name: "Shinbaru", detail: "Website logo", url: "https://x.com/_shinbaru")
      }
      Section("Coin Art") {
        creditRow(
          name: "WindSketchy",
          detail: "Neuro Coin, Evil Coin, and Twins Coin artwork",
          url: "https://x.com/WindSketchy"
        )
      }
      Section("Additional Contributions") {
        creditRow(
          name: "Promote", detail: "Twitch poll vote retrieval; manages Neuro & Evil Quotes")
        creditRow(name: "FlashFire8", detail: "Video gallery editing and uploads")
        creditRow(name: "Rachinova & CJ", detail: "Soundbite creation and editing")
        creditRow(name: "Aferil", detail: "Creator and maintainer of the Karaoke App")
        creditRow(name: "Emuz", detail: "Badge art editing", url: "https://x.com/possiblyemuz")
      }
      Section("Internal Testing & Metadata") {
        Text(
          "Big thanks for assisting with internal testing, bug reporting, and maintaining "
            + "accurate song metadata across the site:\n\n"
            + "flashfire8 • promote. • emuz • germaninfantry • magnettileman • waya13 • "
            + "kyarashard • ttsuyuki • nyss_7 • isrlygood • rachinova • ninjakai03 • "
            + "czadymny • gbritannia • sir_recker • dodo8071795"
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
      }
      Section("Special Thanks") {
        creditRow(
          name: "Waya", detail: "Helped obtain artist permissions from B2",
          url: "https://x.com/waya13")
        creditRow(
          name: "Dodo", detail: "Helped upload a large number of artworks",
          url: "https://x.com/dodo8071795")
      }
      Section("Historical Archive Source") {
        Text(
          "All cover files dated November 26, 2025 and earlier are retrieved from the "
            + "Unofficial Neuro Karaoke Archive (V3).\n\n"
            + "Currently managed by: @ninjakai03 (mm2wood), @turuumgl, @nyss_7, @inforno_fire"
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
      }
      Section("Community Artwork") {
        Text(
          "All artwork displayed on this site is used with explicit permission from the "
            + "respective artists. The following artists have granted permission for their "
            + "artwork to be used on this website:"
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        ForEach(CreditsView.artists, id: \.0) { artist in
          ArtistCreditRow(name: artist.0, link: artist.1)
        }
      }
    }
    .navigationTitle("Credits")
    .navigationBarTitleDisplayMode(.inline)
  }
  @ViewBuilder
  private func creditRow(name: String, detail: String, url: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(name).font(.system(size: 15, weight: .semibold))
      Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
      if let url, let u = URL(string: url) {
        Link(url, destination: u).font(.system(size: 12)).lineLimit(1)
      }
    }
    .padding(.vertical, 2)
  }
  static let artists: [(String, String)] = [
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

private struct ArtistCreditRow: View {
  let name: String
  let link: String
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(name).font(.system(size: 14, weight: .medium))
      if let url = URL(string: link), !link.isEmpty {
        Link(link, destination: url)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text("No socials")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 1)
  }
}

private struct AcknowledgementsView: View {
  private struct Credit: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let url: URL?
  }
  private let credits: [Credit] = [
    Credit(
      name: "SDWebImageSwiftUI",
      detail: "MIT License",
      url: URL(string: "https://github.com/SDWebImage/SDWebImageSwiftUI")
    ),
    Credit(
      name: "SDWebImage",
      detail: "MIT License",
      url: URL(string: "https://github.com/SDWebImage/SDWebImage")
    ),
    Credit(
      name: "SF Symbols",
      detail: "© Apple Inc.",
      url: URL(string: "https://developer.apple.com/sf-symbols/")
    ),
  ]
  var body: some View {
    List(credits) { credit in
      VStack(alignment: .leading, spacing: 4) {
        Text(credit.name)
          .font(.system(size: 15, weight: .semibold))
        Text(credit.detail)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
        if let url = credit.url {
          Link(url.absoluteString, destination: url)
            .font(.system(size: 12))
            .lineLimit(1)
        }
      }
      .padding(.vertical, 2)
    }
    .navigationTitle("Open Source Licenses")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct iOSAppDevelopmentView: View {
  private let repoURL = URL(string: "https://github.com/Evil-Project/Twinskaraoke")!
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("Twinskaraoke iOS")
            .font(.system(size: 17, weight: .semibold))
          Text(
            "A native SwiftUI client for the Neuro & Evil Karaoke Web Player. Built around the public Neurokaraoke API, with offline downloads, karaoke vocal removal, beat-aware crossfade, and Live Radio playback."
          )
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }
      Section("Source Code") {
        Link(destination: repoURL) {
          HStack(spacing: 14) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 28, height: 28)
              .background(Color.black)
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
              Text("github.com/Evil-Project/Twinskaraoke")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
              Text("Open repository")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
      }
      Section("Tech Stack") {
        techRow("SwiftUI", detail: "Declarative UI throughout")
        techRow("AVFoundation", detail: "Playback, crossfade, vocal-cancel audio mix")
        techRow("Combine", detail: "Player and download state")
        techRow("SDWebImageSwiftUI", detail: "Artwork loading & caching")
        techRow("LNPopupUI", detail: "Mini-player popup bar")
      }
      Section("Contributing") {
        Text(
          "Issues and pull requests are welcome on GitHub. The repository contains build instructions and the project's coding conventions."
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
      }
    }
    .navigationTitle("iOS App Development")
    .navigationBarTitleDisplayMode(.inline)
  }
  @ViewBuilder
  private func techRow(_ name: String, detail: String) -> some View {
    HStack {
      Text(name).font(.system(size: 14, weight: .medium))
      Spacer()
      Text(detail)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 1)
  }
}

private struct LinkifiedText: View {
  let text: String
  var body: some View {
    let parts = LinkifiedText.split(text)
    parts.reduce(Text("")) { acc, part in
      switch part {
      case .text(let s):
        return acc + Text(s)
      case .url(let s, let url):
        return acc
          + Text(
            AttributedString(
              s,
              attributes: AttributeContainer([
                .link: url,
                .foregroundColor: UIColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
              ])))
      }
    }
  }

  private enum Part {
    case text(String)
    case url(String, URL)
  }
  private static let detector: NSDataDetector? = {
    try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
  }()
  private static func split(_ string: String) -> [Part] {
    guard let detector else { return [.text(string)] }
    let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
    let matches = detector.matches(in: string, options: [], range: nsRange)
    if matches.isEmpty { return [.text(string)] }
    var parts: [Part] = []
    var cursor = string.startIndex
    for match in matches {
      guard let range = Range(match.range, in: string), let url = match.url else { continue }
      if cursor < range.lowerBound {
        parts.append(.text(String(string[cursor..<range.lowerBound])))
      }
      parts.append(.url(String(string[range]), url))
      cursor = range.upperBound
    }
    if cursor < string.endIndex {
      parts.append(.text(String(string[cursor..<string.endIndex])))
    }
    return parts
  }
}
