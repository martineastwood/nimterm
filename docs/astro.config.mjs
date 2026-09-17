// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightThemeNext from 'starlight-theme-next';

export default defineConfig({
	site: 'https://nimterm.niminal.dev',
	integrations: [
		starlight({
			title: 'nimterm',
			description: 'Build terminal and console apps for agents in Nim: cells, layout, agent-shaped widgets, Markdown, and lifecycle events.',
			favicon: '/favicon.ico',
			head: [
				{ tag: 'link', attrs: { rel: 'icon', href: '/favicon.ico', sizes: '48x48' } },
				{ tag: 'link', attrs: { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32x32.png' } },
				{ tag: 'link', attrs: { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16x16.png' } },
				{ tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' } },
			],
			customCss: ['./src/styles/sidebar.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/martineastwood/nimterm' }],
			sidebar: [
				{ label: 'Introduction', slug: 'introduction' },
				{ label: 'Quickstart', slug: 'guides/quickstart' },
				{ label: 'Application loop', slug: 'guides/application-loop' },
				{ label: 'Widgets', slug: 'guides/widgets' },
				{ label: 'Input and events', slug: 'guides/input-and-events' },
				{ label: 'Terminal backends', slug: 'guides/terminal-backends' },
				{ label: 'Styling and themes', slug: 'guides/styling-and-themes' },
				{ label: 'Text and Markdown', slug: 'guides/text-and-markdown' },
				{ label: 'Agent frontends', slug: 'guides/agent-frontends' },
				{ label: 'Testing', slug: 'guides/testing' },
				{
					label: 'API',
					collapsed: true,
					items: [
						{ label: 'Overview', slug: 'reference/core-api' },
						{ autogenerate: { directory: 'reference/api' } },
					],
				},
			],
			plugins: [starlightThemeNext()],
		}),
	],
});
