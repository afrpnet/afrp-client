'use strict';
'require baseclass';
'require fs';

var UPDATE_CORE = '/usr/libexec/afrp/update-core';

function runJson(args) {
	return fs.exec(UPDATE_CORE, args).then(function(res) {
		var data = null;
		try { data = JSON.parse((res.stdout || '').trim()); } catch (e) { data = null; }
		if (data == null)
			throw new Error(_('脚本未返回有效数据') + '（exit ' + res.code + '）');
		return data;
	});
}

function wait(ms) {
	return new Promise(function(resolve) { setTimeout(resolve, ms); });
}

/* 下载与校验放在设备后台跑，页面只轮询结果。
   同步执行时一次长下载就会撞上 LuCI 的 XHR 超时，
   页面报「安装失败：XHR request timed out」而二进制其实已经装好。 */
return baseclass.extend({
	install: function(url, sha256, onProgress) {
		var started = Date.now();
		var limit = 600000;

		function poll(fails) {
			return runJson(['install-status']).catch(function(err) {
				if (fails < 3)
					return wait(2000).then(function() { return poll(fails + 1); });
				throw err;
			}).then(function(d) {
				if (d.ok != true)
					throw new Error(d.error || _('查询安装进度失败'));
				if (d.done == true) {
					var r = d.result || {};
					if (r.ok != true)
						throw new Error(r.error || _('安装失败'));
					return r;
				}
				var used = Date.now() - started;
				if (used > limit)
					throw new Error(_('安装仍在后台进行，请稍后刷新页面核对 frpc 版本'));
				if (onProgress)
					onProgress(Math.round(used / 1000));
				return wait(2000).then(function() { return poll(0); });
			});
		}

		return runJson(['install-bg', url, sha256]).then(function(d) {
			if (d.ok != true)
				throw new Error(d.error || _('启动安装失败'));
			return poll(0);
		});
	}
});