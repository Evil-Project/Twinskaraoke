import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "Twinskaraoke",
  description: "iOS, iPadOS, tvOS and Apple Watch client of www.twinskaraoke.com",

  locales: {
    root: {
      label: 'English',
      lang: 'en',
      title: "Twinskaraoke",
      description: "iOS, iPadOS, tvOS and Apple Watch client of www.twinskaraoke.com",
      themeConfig: {
        nav: [
          { text: 'Home', link: '/' },
          { text: 'Getting Started', link: '/getting-started' },
          { text: 'Apple TV', link: '/apple-tv' }
        ],

        sidebar: [
          {
            text: 'Installation',
            items: [
              { text: 'Getting Started', link: '/getting-started' },
              { text: 'Build from Source', link: '/build-from-source' }
            ]
          },
          {
            text: 'Apps',
            items: [
              { text: 'Apple TV', link: '/apple-tv' }
            ]
          }
        ],

        socialLinks: [
          { icon: 'github', link: '//github.com/Evil-Project/Twinskaraoke' }
        ]
      }
    },

    zh: {
      label: '简体中文',
      lang: 'zh-CN',
      title: "Twinskaraoke",
      description: "Twinskaraoke.com 的 iOS、iPadOS、tvOS 与 Apple Watch 客户端",
      themeConfig: {
        nav: [
          { text: '首页', link: '/zh/' },
          { text: '快速上手', link: '/zh/getting-started' },
          { text: 'Apple TV', link: '/zh/apple-tv' }
        ],

        sidebar: [
          {
            text: '安装指南',
            items: [
              { text: '快速上手', link: '/zh/getting-started' },
              { text: '从源码构建', link: '/zh/build-from-source' }
            ]
          },
          {
            text: '各平台应用',
            items: [
              { text: 'Apple TV', link: '/zh/apple-tv' }
            ]
          }
        ],

        socialLinks: [
          { icon: 'github', link: '//github.com/Evil-Project/Twinskaraoke' }
        ]
      }
    }
  }
})
