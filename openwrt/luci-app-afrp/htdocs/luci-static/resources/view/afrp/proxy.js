'use strict';
'require view';
'require fs';
'require ui';

var CONFIG_PATH = '/etc/afrp/config.json';

function readConfig() {
	return fs.read(CONFIG_PATH).then(function(raw) {
		try { return JSON.parse(raw); }
		catch (e) { return {}; }
	}).catch(function() { return {}; });
}

function writeConfig(cfg) {
	return fs.write(CONFIG_PATH, JSON.stringify(cfg, null, '\t'));
}

var TYPE_LABELS = {
	tcp: 'tcp', udp: 'udp', http: 'http', https: 'https',
	stcp: 'stcp', sudp: 'sudp', xtcp: 'xtcp'
};

function validateName(v) {
	if (!v) return _('请填写名称');
	if (!/^[A-Za-z0-9_.-]+$/.test(v)) return _('仅支持字母、数字与 . _ -');
	return true;
}

function validatePort(v) {
	if (!v) return true;
	var n = parseInt(v, 10);
	if (isNaN(n) || n < 1 || n > 65535 || String(n) !== v) return _('端口须为 1–65535 的整数');
	return true;
}

return view.extend({
	render: function() {
		var cfg = {};
		var proxies = [];
		var editIdx = -1;

		var msgDiv = E('div', { style: 'padding:0' }, '');
		var tableBody = E('tbody', {});
		var formWrap = E('div', { style: 'display:none' });

		/* ---------- 表单字段 ---------- */

		var fEnabled = E('input', { type: 'checkbox', checked: 'checked' });
		var fName = E('input', { type: 'text', class: 'cbi-input-text', style: 'width:120px' });
		var fType = E('select', { class: 'cbi-input-select' });
		['tcp','udp','http','https','stcp','sudp','xtcp'].forEach(function(t) {
			fType.appendChild(E('option', { value: t }, [ TYPE_LABELS[t] ]));
		});
		var fLocalIp = E('input', { type: 'text', class: 'cbi-input-text', style: 'width:120px', value: '127.0.0.1' });
		var fLocalPort = E('input', { type: 'text', class: 'cbi-input-text', style: 'width:80px' });
		var fRemotePort = E('input', { type: 'text', class: 'cbi-input-text', style: 'width:80px' });
		var fSubdomain = E('input', { type: 'text', class: 'cbi-input-text', style: 'width:120px' });
		var fCustomDomain = E('input', { type: 'text', class: 'cbi-input-text', style: 'width:180px' });
		var fSecretKey = E('input', { type: 'password', class: 'cbi-input-text', style: 'width:160px' });

		var rowRemote = E('div', { class: 'cbi-value' });
		var rowHttp = E('div', { class: 'cbi-value' });
		var rowSecret = E('div', { class: 'cbi-value' });

		function updateFieldVisibility() {
			var t = fType.value;
			rowRemote.style.display = (t === 'tcp' || t === 'udp') ? '' : 'none';
			rowHttp.style.display = (t === 'http' || t === 'https') ? '' : 'none';
			rowSecret.style.display = (t === 'stcp' || t === 'sudp' || t === 'xtcp') ? '' : 'none';
		}
		fType.addEventListener('change', updateFieldVisibility);

		function clearForm() {
			fEnabled.checked = true;
			fName.value = '';
			fType.value = 'tcp';
			fLocalIp.value = '127.0.0.1';
			fLocalPort.value = '';
			fRemotePort.value = '';
			fSubdomain.value = '';
			fCustomDomain.value = '';
			fSecretKey.value = '';
			editIdx = -1;
			updateFieldVisibility();
		}

		function fillForm(idx) {
			var p = proxies[idx];
			fEnabled.checked = !!p.enabled;
			fName.value = p.name || '';
			fType.value = p.type || 'tcp';
			fLocalIp.value = p.local_ip || '127.0.0.1';
			fLocalPort.value = p.local_port || '';
			fRemotePort.value = p.remote_port || '';
			fSubdomain.value = p.subdomain || '';
			fCustomDomain.value = p.custom_domain || '';
			fSecretKey.value = p.secret_key || '';
			editIdx = idx;
			updateFieldVisibility();
		}

		function collectForm() {
			return {
				enabled: fEnabled.checked,
				name: fName.value.trim(),
				type: fType.value,
				local_ip: fLocalIp.value.trim(),
				local_port: fLocalPort.value.trim(),
				remote_port: fRemotePort.value.trim(),
				subdomain: fSubdomain.value.trim(),
				custom_domain: fCustomDomain.value.trim(),
				secret_key: fSecretKey.value
			};
		}

		/* ---------- 渲染表格 ---------- */

		function renderTable() {
			tableBody.textContent = '';
			if (!proxies.length) {
				tableBody.appendChild(E('tr', {}, [
					E('td', { colspan: 6, style: 'text-align:center;color:#999;padding:12px' },
						[ _('暂无隧道，点击下方按钮添加') ])
				]));
				return;
			}
			for (var i = 0; i < proxies.length; i++) {
				(function(idx) {
					var p = proxies[idx];
					var t = p.type || 'tcp';
					var remoteInfo = '';
					if (t === 'tcp' || t === 'udp') {
						remoteInfo = p.remote_port || _('自动');
					} else if (t === 'http' || t === 'https') {
						remoteInfo = p.custom_domain || (p.subdomain ? p.subdomain + '.…' : '—');
					} else {
						remoteInfo = '—';
					}
					var tr = E('tr', { class: 'cbi-section-table-row' }, [
						E('td', { class: 'cbi-value-field', style: 'width:40px;text-align:center' }, [
							E('input', { type: 'checkbox', disabled: 'disabled', checked: p.enabled ? 'checked' : null })
						]),
						E('td', {}, [ p.name || '—' ]),
						E('td', {}, [ t ]),
						E('td', {}, [ (p.local_ip || '127.0.0.1') + ':' + (p.local_port || '?') ]),
						E('td', {}, [ remoteInfo ]),
						E('td', { style: 'white-space:nowrap' }, [
							E('button', { class: 'cbi-button cbi-button-edit', style: 'margin-right:4px' }, [ _('编辑') ]),
							E('button', { class: 'cbi-button cbi-button-remove' }, [ _('删除') ])
						])
					]);
					var btns = tr.querySelectorAll('button');
					btns[0].addEventListener('click', function() {
						fillForm(idx);
						formWrap.style.display = '';
						window.scrollTo(0, formWrap.offsetTop - 20);
					});
					btns[1].addEventListener('click', function() {
						proxies.splice(idx, 1);
						saveProxies(_('隧道已删除'));
					});
					tableBody.appendChild(tr);
				})(i);
			}
		}

		function saveProxies(msg) {
			cfg.proxies = proxies;
			writeConfig(cfg).then(function() {
				msgDiv.textContent = msg || _('已保存');
				renderTable();
				return fs.exec('/etc/init.d/afrp', ['restart']);
			}).catch(function() {
				msgDiv.textContent = _('保存失败');
			});
		}

		/* ---------- 表单按钮 ---------- */

		var btnSave = E('button', { class: 'cbi-button cbi-button-apply' }, [ _('保存') ]);
		btnSave.addEventListener('click', function() {
			var p = collectForm();
			var vn = validateName(p.name);
			if (vn !== true) { msgDiv.textContent = vn; return; }
			if (!p.local_port) { msgDiv.textContent = _('请填写本地端口'); return; }
			var vp = validatePort(p.local_port);
			if (vp !== true) { msgDiv.textContent = vp; return; }
			if (p.remote_port) {
				var vr = validatePort(p.remote_port);
				if (vr !== true) { msgDiv.textContent = vr; return; }
			}
			if (editIdx >= 0) {
				proxies[editIdx] = p;
			} else {
				proxies.push(p);
			}
			clearForm();
			formWrap.style.display = 'none';
			saveProxies(editIdx >= 0 ? _('隧道已更新') : _('隧道已添加'));
		});

		var btnCancel = E('button', { class: 'cbi-button' }, [ _('取消') ]);
		btnCancel.addEventListener('click', function() {
			clearForm();
			formWrap.style.display = 'none';
		});

		var btnAdd = E('button', { class: 'cbi-button cbi-button-add' }, [ _('添加隧道') ]);
		btnAdd.addEventListener('click', function() {
			clearForm();
			formWrap.style.display = '';
			fName.focus();
		});

		/* ---------- 页面布局 ---------- */

		var table = E('table', { class: 'cbi-section-table' }, [
			E('thead', {}, [
				E('tr', { class: 'cbi-section-table-titles' }, [
					E('th', { style: 'width:40px' }, [ _('启用') ]),
					E('th', {}, [ _('名称') ]),
					E('th', {}, [ _('类型') ]),
					E('th', {}, [ _('本地地址') ]),
					E('th', {}, [ _('远程') ]),
					E('th', {}, [ _('操作') ])
				])
			]),
			tableBody
		]);

		rowRemote.appendChild(E('label', { class: 'cbi-value-title' }, [ _('远程端口') ]));
		rowRemote.appendChild(E('div', { class: 'cbi-value-field' }, [ fRemotePort ]));

		rowHttp.appendChild(E('label', { class: 'cbi-value-title' }, [ _('子域名 / 自定义域名') ]));
		rowHttp.appendChild(E('div', { class: 'cbi-value-field', style: 'display:flex;gap:6px' }, [
			fSubdomain, E('span', { style: 'line-height:30px' }, ['/']), fCustomDomain
		]));

		rowSecret.appendChild(E('label', { class: 'cbi-value-title' }, [ _('密钥') ]));
		rowSecret.appendChild(E('div', { class: 'cbi-value-field' }, [ fSecretKey ]));

		formWrap.appendChild(E('div', { class: 'cbi-section' }, [
			E('div', { class: 'cbi-section-node' }, [
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('启用') ]),
					E('div', { class: 'cbi-value-field' }, [
						E('span', {}, [ fEnabled ])
					])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('名称') ]),
					E('div', { class: 'cbi-value-field' }, [ fName ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('类型') ]),
					E('div', { class: 'cbi-value-field' }, [ fType ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('本地 IP') ]),
					E('div', { class: 'cbi-value-field' }, [ fLocalIp ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ _('本地端口') ]),
					E('div', { class: 'cbi-value-field' }, [ fLocalPort ])
				]),
				rowRemote,
				rowHttp,
				rowSecret,
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, [ '\u00A0' ]),
					E('div', { class: 'cbi-value-field', style: 'display:flex;gap:8px' }, [
						btnSave, btnCancel
					])
				])
			])
		]));

		var page = E('div', { class: 'cbi-map' }, [
			E('h2', {}, [ _('隧道管理') ]),
			E('p', { class: 'cbi-map-descr' }, [
				_('每条隧道对应一个本地服务。远程端口（tcp/udp）留空时由服务器自动分配；http/https 填自定义域名或子域名。')
			]),
			E('div', { class: 'cbi-section' }, [
				E('div', { class: 'cbi-section-node' }, [
					E('div', { class: 'cbi-value' }, [
						E('label', { class: 'cbi-value-title' }, [ '\u00A0' ]),
						E('div', { class: 'cbi-value-field' }, [ msgDiv ])
					])
				])
			]),
			E('div', { class: 'cbi-section' }, [
				table,
				E('div', { style: 'padding:8px 0' }, [ btnAdd ])
			]),
			formWrap
		]);

		return readConfig().then(function(c) {
			cfg = c;
			proxies = Array.isArray(c.proxies) ? c.proxies : [];
			renderTable();
			return page;
		});
	}
});
