var l = window.onload;
window.onload = function() {
	var e = document.getElementsByTagName('a');
	for (var i=0; i<e.length; i++) {
		e[i].target = 'main';
	}
	l();
}