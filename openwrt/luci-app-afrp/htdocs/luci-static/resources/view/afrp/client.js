'use strict';
'require view';
'require fs';
'require ui';

var IMPORT_ACCOUNT = '/usr/libexec/afrp/import-account';
var UPDATE_CORE = '/usr/libexec/afrp/update-core';
var CONFIG_PATH = '/etc/afrp/config.json';
var DEFAULT_BASE = 'https://www.afrp.net';
var DEFAULT_TOKEN_ENDPOINT = 'https://www.afrp.net/oidc/token.php';

function copyText(text) {
	if (navigator.clipboard && window.isSecureContext)
		return navigator.clipboard.writeText(text);
	var ta = document.createElement('textarea');
	ta.value = text;
	ta.style.position = 'fixed';
	ta.style.opacity = '0';
	document.body.appendChild(ta);
	ta.select();
	try { document.execCommand('copy'); } catch (e) {}
	document.body.removeChild(ta);
	return Promise.resolve();
}

function readConfig() {
	return fs.read(CONFIG_PATH).then(function(raw) {
		try { return JSON.parse(raw); }
		catch (e) { return {}; }
	}).catch(function() { return {}; });
}

function writeConfig(cfg) {
	return fs.write(CONFIG_PATH, JSON.stringify(cfg, null, '\t'));
}

return view.extend({
	render: function() {
		var cfg = {};
		var lastServers = [];
		var lastSite = DEFAULT_BASE;
		var currentUsername = '';

		/* ---------- DOM 元素 ---------- */

		var chkEnabled = E('input', { type: 'checkbox' });
		chkEnabled.addEventListener('change', function() {
			cfg.enabled = chkEnabled.checked;
			writeConfig(cfg);
		});
		var inpUsername = E('input', { type: 'text', class: 'cbi-input-text', placeholder: _('官网账号用户名或邮箱') });
		var wrapPassword = E('div', { style: 'display:flex;align-items:center;gap:8px' });
		var inpPassword = E('input', { type: 'password', class: 'cbi-input-password', placeholder: _('官网账号登录密码') });
		var btnTogglePwd = E('button', { type: 'button', class: 'cbi-button cbi-button-apply', style: 'flex-shrink:0;padding:4px 8px;cursor:pointer' }, ['👁']);
		wrapPassword.appendChild(inpPassword);
		wrapPassword.appendChild(btnTogglePwd);

		var btnLogin = E('button', { type: 'button', class: 'cbi-button cbi-button-action' }, [ _('登录') ]);
		var resultDiv = E('div', { style: 'padding:0' }, '');
		var srvArea = E('div', { style: 'padding:0' }, '');
		var secretArea = E('div', { style: 'padding:0' }, '');
		var frpcStatus = E('div', { style: 'padding:0' }, '');

		/* ---------- 密码显隐切换 ---------- */

		btnTogglePwd.addEventListener('click', function() {
			if (inpPassword.type === 'password') {
				inpPassword.type = 'text';
				btnTogglePwd.textContent = '🙈';
			} else {
				inpPassword.type = 'password';
				btnTogglePwd.textContent = '👁';
			}
		});

		/* ---------- 页面布局 ---------- */

		var formSection = E('div', { class: 'cbi-section' }, [
			E('div', { class: 'cbi-section-node' }, [
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('启用服务') ]),
					E('div', { class: 'cbi-value-field' }, [
						E('span', {}, [ chkEnabled ])
					])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('用户名') ]),
					E('div', { class: 'cbi-value-field' }, [ inpUsername ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('密码') ]),
					E('div', { class: 'cbi-value-field' }, [ wrapPassword ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ '\u00A0' ]),
					E('div', { class: 'cbi-value-field' }, [ btnLogin ])
				])
			])
		]);

		var actionCard = E('div', { class: 'cbi-section' }, [
			E('div', { class: 'cbi-section-node' }, [
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ '\u00A0' ]),
					E('div', { class: 'cbi-value-field' }, [ resultDiv ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('可用服务器') ]),
					E('div', { class: 'cbi-value-field' }, [ srvArea ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('Client Secret') ]),
					E('div', { class: 'cbi-value-field' }, [ secretArea ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('frpc 状态') ]),
					E('div', { class: 'cbi-value-field' }, [ frpcStatus ])
				])
			])
		]);

		var page = E('div', { class: 'cbi-map' }, [
			E('h2', {}, [ _('AFRP 内网穿透') ]),
			E('p', { class: 'cbi-map-descr' }, [ _('登录官网账号后选择服务器，所有配置自动填入。') ]),
			formSection,
			actionCard
		]);

		btnLogin.addEventListener('click', function() { doLogin(); });

		/* ---------- 加载配置并填充 ---------- */

		return readConfig().then(function(c) {
			cfg = c;
			chkEnabled.checked = !!cfg.enabled;
			inpUsername.value = cfg.username || '';
			inpPassword.value = cfg.password || '';
			currentUsername = cfg.client_id || '';
			lastSite = cfg.update_base || DEFAULT_BASE;

			var stored = cfg.import_servers;
			if (Array.isArray(stored) && stored.length) {
				lastServers = stored;
				renderServers(stored, lastSite, cfg.server_addr);
			}
			renderSecretInput();
			checkFrpc();
			return page;
		});

		/* ---------- frpc 安装检测 ---------- */

		function checkFrpc() {
			return fs.exec(UPDATE_CORE, ['status']).then(function(res) {
				var d = null;
				try { d = JSON.parse((res.stdout || '').trim()); } catch (e) { d = null; }
				if (!d || !d.ok) {
					frpcStatus.textContent = _('无法检测 frpc 状态');
					return;
				}
				if (d.installed) {
					frpcStatus.textContent = _('frpc 已安装：') + d.version + '（' + d.arch + '）';
				} else {
					frpcStatus.textContent = _('frpc 未安装，正在自动安装…');
					return autoInstallFrpc(d.arch);
				}
			}).catch(function() {
				frpcStatus.textContent = _('frpc 状态检测失败');
			});
		}

		function autoInstallFrpc(arch) {
			return fs.exec(UPDATE_CORE, ['check', DEFAULT_BASE, arch || '']).then(function(res) {
				var d = null;
				try { d = JSON.parse((res.stdout || '').trim()); } catch (e) { d = null; }
				if (!d || !d.ok || !d.candidates || !d.candidates.length) {
					frpcStatus.textContent = _('未找到可用的 frpc 版本');
					return;
				}
				var c = d.candidates[0];
				return fs.exec(UPDATE_CORE, ['install', c.url, c.sha256, c.file]).then(function(res2) {
					var d2 = null;
					try { d2 = JSON.parse((res2.stdout || '').trim()); } catch (e) { d2 = null; }
					if (d2 && d2.ok) {
						frpcStatus.textContent = _('frpc 已自动安装：') + d2.version;
					} else {
						frpcStatus.textContent = _('frpc 自动安装失败：') + (d2 ? d2.error : '');
					}
				});
			}).catch(function() {
				frpcStatus.textContent = _('frpc 自动安装失败');
			});
		}

		/* ---------- 登录 ---------- */

		function getCredentials() {
			return {
				identity: inpUsername.value.trim(),
				password: inpPassword.value
			};
		}

		function doLogin() {
			var creds = getCredentials();
			var identity = creds.identity;
			var password = creds.password;

			resultDiv.textContent = '';
			srvArea.textContent = '';
			secretArea.textContent = '';

			if (!identity || !password) {
				resultDiv.textContent = _('请填写用户名和密码');
				return;
			}

			btnLogin.disabled = true;
			resultDiv.textContent = _('正在登录并获取配置…');

			var req = JSON.stringify({ site: DEFAULT_BASE, rotate: false });
			var login = JSON.stringify({ identity: identity, password: password, device: 'LuCI (OpenWrt)' });

			return fs.write('/tmp/afrp-import.json', req, 384).then(function() {
				return fs.write('/tmp/afrp-login.json', login, 384);
			}).then(function() {
				return fs.exec(IMPORT_ACCOUNT, []);
			}).then(function(res) {
				var d = null;
				try { d = JSON.parse((res.stdout || '').trim()); } catch (e) { d = null; }
				if (d == null)
					throw new Error(_('导入脚本未返回有效数据') + '（exit ' + res.code + '）');
				if (d.ok != true)
					throw new Error(d.error || _('登录失败'));
				return applyLogin(d);
			}).catch(function(err) {
				resultDiv.textContent = _('登录失败：') + err.message;
			}).then(function() {
				btnLogin.disabled = false;
			});
		}

		function applyLogin(d) {
			var loginCfg = d.config || {};
			currentUsername = (d.user && d.user.username) ? d.user.username : '';

			cfg.update_base = d.site || DEFAULT_BASE;
			cfg.token_endpoint = loginCfg.token_endpoint || DEFAULT_TOKEN_ENDPOINT;
			cfg.audience = loginCfg.oidc_audience || 'afrp.net';
			cfg.scope = loginCfg.oidc_scope || 'afrp';
			cfg.username = inpUsername.value.trim();
			cfg.password = inpPassword.value;
			if (currentUsername)
				cfg.client_id = currentUsername;

			return writeConfig(cfg).then(function() {
				var msg = [_('登录成功')];
				if (currentUsername)
					msg.push(_('账号') + ' ' + currentUsername);
				resultDiv.textContent = msg.join('；') + '。';

				if (d.servers && d.servers.length) {
					lastServers = d.servers;
					lastSite = d.site || DEFAULT_BASE;
					cfg.import_servers = d.servers;
					writeConfig(cfg);
					renderServers(d.servers, lastSite, cfg.server_addr);
				}
				renderSecretInput();
			});
		}

		/* ---------- Client Secret ---------- */

		function renderSecretInput() {
			secretArea.textContent = '';
			var row = E('div', { style: 'display:flex;align-items:center;gap:8px' });

			var input = E('input', { type: 'password', class: 'cbi-input-text', placeholder: _('手动填写或点击右侧重置获取'), style: 'flex:1;min-width:150px' });
			if (cfg.client_secret) input.value = cfg.client_secret;

			var btnToggleSecret = E('button', { type: 'button', class: 'cbi-button cbi-button-apply', style: 'flex-shrink:0;padding:4px 8px;cursor:pointer' }, ['👁']);
			btnToggleSecret.addEventListener('click', function() {
				if (input.type === 'password') {
					input.type = 'text';
					btnToggleSecret.textContent = '🙈';
				} else {
					input.type = 'password';
					btnToggleSecret.textContent = '👁';
				}
			});

			input.addEventListener('change', function() {
				cfg.client_secret = input.value.trim();
				writeConfig(cfg);
			});

			var btnReset = E('button', { class: 'cbi-button cbi-button-action' }, [ _('重置并获取') ]);
			btnReset.addEventListener('click', function() {
				if (!currentUsername) {
					resultDiv.textContent = _('请先登录');
					return;
				}
				btnReset.disabled = true;
				btnReset.textContent = _('重置中…');
				doResetSecret().then(function(secret) {
					input.value = secret;
					cfg.client_secret = secret;
					writeConfig(cfg);
					resultDiv.textContent = _('Client Secret 已重置并填入');
				}).catch(function(err) {
					resultDiv.textContent = _('重置失败：') + err.message;
				}).then(function() {
					btnReset.disabled = false;
					btnReset.textContent = _('重置并获取');
				});
			});

			var btnCopy = E('button', { class: 'cbi-button' }, [ _('复制') ]);
			btnCopy.addEventListener('click', function() {
				var v = input.value.trim();
				if (!v) return;
				copyText(v).then(function() {
					btnCopy.textContent = _('已复制');
					window.setTimeout(function() { btnCopy.textContent = _('复制'); }, 2000);
				});
			});

			row.appendChild(input);
			row.appendChild(btnToggleSecret);
			row.appendChild(btnReset);
			row.appendChild(btnCopy);
			secretArea.appendChild(row);
			secretArea.appendChild(E('p', { class: 'cbi-map-descr' }, [ _('重置后旧值立即失效，请妥善保存。') ]));
		}

		function doResetSecret() {
			var base = (cfg.update_base || DEFAULT_BASE).replace(/\/+$/, '');
			var uid = cfg.client_id || '';
			if (!uid) return Promise.reject(new Error('未获取到用户名'));

			var req = JSON.stringify({ site: base, rotate: true });
			var login = JSON.stringify({ identity: uid, password: '', device: 'LuCI (OpenWrt)' });

			return fs.write('/tmp/afrp-import.json', req, 384).then(function() {
				return fs.write('/tmp/afrp-login.json', login, 384);
			}).then(function() {
				return fs.exec(IMPORT_ACCOUNT, []);
			}).then(function(res) {
				var d = null;
				try { d = JSON.parse((res.stdout || '').trim()); } catch (e) { d = null; }
				if (d && d.ok && d.secret) return d.secret;
				throw new Error((d && d.rotate_error) ? d.rotate_error : _('重置失败'));
			});
		}

		/* ---------- 服务器选择 ---------- */

		function renderServers(servers, site, currentAddr) {
			lastServers = servers;
			lastSite = site;
			cfg.import_servers = servers;
			writeConfig(cfg);

			srvArea.textContent = '';
			var sel = E('select', { class: 'cbi-input-select', style: 'min-width:280px' });

			var selectedIdx = 0;
			for (var i = 0; i < servers.length; i++) {
				var sv = servers[i];
				if (currentAddr && sv.addr === currentAddr) {
					selectedIdx = i;
				}
				sel.appendChild(E('option', { value: String(i) },
					[ (sv.name || ('#' + sv.id)) + '（' + (sv.addr || '') + ':' + (sv.port || 0) + '）' +
						(sv.location ? ' · ' + sv.location : '') ]));
			}
			sel.value = String(selectedIdx);

			var btn = E('button', { class: 'cbi-button cbi-button-apply' }, [ _('使用此服务器') ]);
			btn.addEventListener('click', function() {
				var sv = servers[parseInt(sel.value, 10)] || null;
				if (!sv) return;
				cfg.server_addr = String(sv.addr || '');
				cfg.server_port = String(sv.port || 7000);
				cfg.enabled = true;
				chkEnabled.checked = true;
				writeConfig(cfg).then(function() {
					resultDiv.textContent = _('已选择服务器：') + (sv.name || sv.addr) +
						('（' + sv.addr + ':' + sv.port + '）。');
				});
			});
			srvArea.appendChild(E('div', { style: 'display:flex;align-items:center;gap:8px' }, [ sel, btn ]));
		}
	}
});
