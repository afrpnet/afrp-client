'use strict';
'require view';
'require fs';
'require rpc';

var CONFIG_PATH = '/etc/afrp/config.json';

var callLogRead = rpc.declare({
	object: 'log',
	method: 'read',
	params: [ 'lines' ],
	expect: { '': {} }
});

var UPDATE_CORE = '/usr/libexec/afrp/update-core';
var INITD = '/etc/init.d/afrp';

function cmpVer(a, b) {
	function parts(v) {
		return String(v || '').replace(/^[vV]/, '').split('.').map(function(s) {
			var m = /^\d+/.exec(s);
			return m ? parseInt(m[0], 10) : 0;
		});
	}
	var pa = parts(a), pb = parts(b);
	var n = Math.max(pa.length, pb.length);
	for (var i = 0; i < n; i++) {
		var x = i < pa.length ? pa[i] : 0;
		var y = i < pb.length ? pb[i] : 0;
		if (x != y)
			return x < y ? -1 : 1;
	}
	return 0;
}

function pickBest(list, arch) {
	var best = null;
	for (var i = 0; i < list.length; i++) {
		var e = list[i];
		if (best == null) {
			best = e;
			continue;
		}
		var eExact = !!(arch && e.arch && e.arch == arch);
		var bExact = !!(arch && best.arch && best.arch == arch);
		if (eExact != bExact) {
			if (eExact)
				best = e;
		}
		else if (cmpVer(e.version, best.version) > 0) {
			best = e;
		}
	}
	return best;
}

function runJson(cmd, args) {
	return fs.exec(cmd, args).then(function(res) {
		var out = (res.stdout || '').trim();
		var data = null;
		try { data = JSON.parse(out); } catch (e) { data = null; }
		if (data == null)
			throw new Error(_('脚本未返回有效数据') + '（exit ' + res.code + '）');
		return data;
	});
}

function sizeText(size) {
	size = parseInt(size, 10) || 0;
	if (size >= 1 << 20)
		return (size / (1 << 20)).toFixed(1) + ' MB';
	if (size >= 1 << 10)
		return Math.round(size / (1 << 10)) + ' KB';
	return size > 0 ? size + ' B' : '';
}

return view.extend({
	render: function() {
		var state = {
			enabled: false,
			installed: false,
			running: false,
			version: '',
			arch: ''
		};

		/* ---------------- 卡片 1：服务状态 ---------------- */

		var svcInfo = E('span', {}, [ _('加载中…') ]);
		var svcNote = E('span', { class: 'cbi-map-descr' }, '');
		var btnStart = E('button', { class: 'cbi-button cbi-button-apply' }, [ _('启动') ]);
		var btnStop = E('button', { class: 'cbi-button cbi-button-reset' }, [ _('停止') ]);
		var btnRestart = E('button', { class: 'cbi-button cbi-button-action' }, [ _('重启') ]);
		var btnRefreshSvc = E('button', { class: 'cbi-button' }, [ _('刷新') ]);

		function renderStatus() {
			var parts = [];
			parts.push(state.running ? _('运行中') : _('未运行'));
			parts.push(state.installed ? ('frpc v' + state.version) : _('未安装核心'));
			if (state.arch)
				parts.push(_('架构') + ' ' + state.arch);
			svcInfo.textContent = parts.join(' · ');
			svcNote.textContent = state.enabled
				? _('开机自启：已启用')
				: _('开机自启：未启用（在「基础设置」勾选「启用服务」）');
		}

		function refreshStatus() {
			return runJson(UPDATE_CORE, [ 'status' ]).then(function(d) {
				if (d.ok != true)
					throw new Error(d.error || _('状态读取失败'));
				state.installed = d.installed == true;
				state.running = d.running == true;
				state.version = d.version || '';
				state.arch = d.arch || '';
				renderStatus();
			}).catch(function(err) {
				svcInfo.textContent = _('状态读取失败：') + err.message;
				svcNote.textContent = '';
			});
		}

		function serviceAction(action) {
			svcNote.textContent = _('正在执行') + ' ' + action + ' …';
			return fs.exec(INITD, [ action ]).then(function(res) {
				var msg = (res.stderr || res.stdout || '').trim();
				svcNote.textContent = _('已执行') + ' ' + action +
					'（exit ' + res.code + '）' + (msg ? '：' + msg : '');
				window.setTimeout(function() { refreshStatus(); }, 1500);
			});
		}

		btnStart.addEventListener('click', function() { serviceAction('start'); });
		btnStop.addEventListener('click', function() { serviceAction('stop'); });
		btnRestart.addEventListener('click', function() { serviceAction('restart'); });
		btnRefreshSvc.addEventListener('click', function() { refreshStatus(); });

		var cardSvc = E('div', { class: 'cbi-section' }, [
			E('h3', {}, [ _('服务状态') ]),
			E('p', {}, [ svcInfo ]),
			E('p', {}, [ svcNote ]),
			E('div', {}, [ btnStart, ' ', btnStop, ' ', btnRestart, ' ', btnRefreshSvc ])
		]);

		/* ---------------- 卡片 2：frpc 核心更新 ---------------- */

		var coreInfo = E('div', {}, [ _('点击「检查更新」获取可用核心。') ]);
		var coreDetail = E('div', { class: 'cbi-map-descr' }, '');
		var btnCheck = E('button', { class: 'cbi-button cbi-button-action' }, [ _('检查更新') ]);
		var installBtn = null;

		function doCheckCore() {
			btnCheck.disabled = true;
			installBtn = null;
			coreInfo.textContent = _('正在检查…');
			coreDetail.textContent = '';

			var ub = '';
			try {
				var rawCfg = fs.read(CONFIG_PATH);
				var parsed = JSON.parse(rawCfg);
				ub = (parsed.update_base || '').trim();
			} catch (e) {}
			var base = ub ? ub.replace(/\/+$/, '') : 'https://www.afrp.net';

			return runJson(UPDATE_CORE, [ 'check', base, '' ]).then(function(d) {
				if (d.ok != true)
					throw new Error(d.error || _('检查失败'));
				state.version = d.current_version || state.version;
				state.arch = d.arch || state.arch;
				state.installed = state.installed || !!d.current_version;
				renderStatus();

				var best = pickBest(d.candidates || [], d.arch);
				if (!best) {
					coreInfo.textContent = _('未找到适用于当前架构（' + (d.arch || '未知') + '）的核心条目。');
					coreDetail.textContent = _('可稍后再试，或到官网下载页手动获取。');
					return;
				}

				var head = _('最新版本') + ' v' + best.version +
					(best.arch ? '（' + best.arch + '）' : '') +
					(best.size ? '，' + sizeText(best.size) : '') +
					(best.date ? '，' + best.date : '');
				var notes = best.notes ? '\n' + best.notes : '';

				if (!d.current_version) {
					coreInfo.textContent = head + _('。本机尚未安装 frpc 核心。');
				}
				else if (cmpVer(best.version, d.current_version) > 0) {
					coreInfo.textContent = head + '，' + _('当前 v' + d.current_version + '，可更新。');
				}
				else {
					coreInfo.textContent = _('已是最新版本（v' + d.current_version + '）。');
					coreDetail.textContent = head + notes;
					return;
				}
				coreDetail.textContent = head + notes;

				if (!best.sha256) {
					coreDetail.textContent += '\n' + _('该条目缺少 SHA-256 校验值，无法在线安装，请到官网下载页手动安装。');
					return;
				}
				if (state.running)
					coreDetail.textContent += '\n' + _('提示：安装完成后需重启服务生效。');

				installBtn = E('button', { class: 'cbi-button cbi-button-apply' }, [ _('下载并安装 v' + best.version) ]);
				installBtn.addEventListener('click', function() { doInstallCore(best, installBtn); });
				coreDetail.appendChild(E('p', {}, [ installBtn ]));
			}).catch(function(err) {
				coreInfo.textContent = _('检查失败：') + err.message;
			}).then(function() {
				btnCheck.disabled = false;
			});
		}

		function doInstallCore(entry, btn) {
			if (!window.confirm(_('将下载并替换 frpc 核心（先校验 SHA-256），随后需要重启服务才能生效。继续？')))
				return;
			btn.disabled = true;
			coreInfo.textContent = _('正在下载并校验…文件较大时可能需要数十秒，请勿关闭页面。');
			return fs.exec(UPDATE_CORE, [ 'install', entry.url, entry.sha256, entry.file ]).then(function(res) {
				var d = null;
				try { d = JSON.parse((res.stdout || '').trim()); } catch (e) { d = null; }
				if (d == null || d.ok != true)
					throw new Error(d && d.error ? d.error : (_('安装失败') + '（exit ' + res.code + '）'));
				coreInfo.textContent = _('安装成功：frpc v' + d.version + '。请点击上方「重启」使新核心生效。');
			}).catch(function(err) {
				coreInfo.textContent = _('安装失败：') + err.message;
			}).then(function() {
				btn.disabled = false;
				return refreshStatus();
			});
		}

		btnCheck.addEventListener('click', function() { doCheckCore(); });

		var cardCore = E('div', { class: 'cbi-section' }, [
			E('h3', {}, [ _('frpc 核心更新') ]),
			coreInfo,
			coreDetail,
			E('div', {}, [ btnCheck ])
		]);

		/* ---------------- 卡片 3：日志 ---------------- */

		var logBox = E('pre', {
			style: 'max-height:320px;overflow:auto;white-space:pre-wrap;word-break:break-all;margin:0'
		}, _('加载中…'));
		var btnLog = E('button', { class: 'cbi-button' }, [ _('刷新') ]);
		var btnClear = E('button', { class: 'cbi-button cbi-button-reset' }, [ _('清空') ]);

		function loadLog() {
			return callLogRead(200).then(function(res) {
				if (res && typeof res.log == 'string' && res.log.length)
					return res.log;
				throw new Error('empty');
			}).catch(function() {
				return fs.exec('/sbin/logread', []).then(function(r) {
					if (r.stdout)
						return r.stdout;
					throw new Error('empty');
				});
			}).then(function(text) {
				var lines = text.split('\n').filter(function(l) {
					return /afrp|frpc/i.test(l);
				});
				lines = lines.slice(-50);
				logBox.textContent = lines.length
					? lines.join('\n')
					: _('暂无 afrp / frpc 相关日志');
			}).catch(function() {
				logBox.textContent = _('读取日志失败。可在 SSH 中执行：logread | grep -i afrp');
			});
		}

		btnLog.addEventListener('click', function() { loadLog(); });
		btnClear.addEventListener('click', function() { logBox.textContent = ''; });

		var cardLog = E('div', { class: 'cbi-section' }, [
			E('h3', {}, [ _('日志') ]),
			logBox,
			E('p', {}, [ btnLog, ' ', btnClear ])
		]);

		var page = E('div', { class: 'cbi-map' }, [
			E('h2', {}, [ _('AFRP 内网穿透 运行状态') ]),
			cardSvc,
			cardCore,
			cardLog
		]);

		return fs.read(CONFIG_PATH).then(function(raw) {
			try {
				var c = JSON.parse(raw);
				state.enabled = !!c.enabled;
			} catch (e) {}
			refreshStatus();
			loadLog();
			return page;
		}).catch(function() {
			refreshStatus();
			loadLog();
			return page;
		});
	}
});
