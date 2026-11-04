-- 指挥 Finder 把挂载卷的窗口布局写进 .DS_Store（卷名与 tool/make-dmg.sh 的 VOL 一致）
-- 窗口 660x420、图标 112、两个图标落在背景图预留的槽位（190,265 / 470,265）
tell application "Finder"
	tell disk "AFRP OIDC Client"
		open
		delay 2
		set w to container window
		set current view of w to icon view
		set toolbar visible of w to false
		set statusbar visible of w to false
		set bounds of w to {100, 100, 760, 520}
		set vo to icon view options of w
		set arrangement of vo to not arranged
		set icon size of vo to 112
		set background picture of vo to file ".background:background.tiff"
		set position of item "AFRP OIDC Client.app" of w to {190, 265}
		set position of item "Applications" of w to {470, 265}
		update w without registering applications
		delay 3
		close w
	end tell
end tell
