$(document).ready(function() {
	
	var timeMin = commits[0].timestamp;
	var timeMax = commits[commits.length - 1].timestamp;
	var timeRange = timeMax - timeMin;
	
	var highlightMode = 'author';
	var selectedAuthorId = undefined;
	var selectedCommit = undefined;
	var selectedGroupId = 'overall';
	var highlightedCommit = undefined;
	var dateFrom = new Date(timeMin * 1000);
	var dateTo = new Date(timeMax * 1000);
	
	var guiUpdate = false;
	var sortColumn = 1;
	var sortReverse = false;
	
	var $window = $(window);
	var $document = $(document);
	var $minimap = $('#minimap');
	var $spans = $('.cregit-span');
	var $content = $('#source-content');
	var $minimapView = $('#minimap-view-shade,#minimap-view-frame');
	var $navbar = $('#navbar');
	var $contributor_rows = $(".contributor-row");
	var $contributor_headers = $(".table-header-row > th");
	var $highlightSelect = $('#select-highlighting');
	var $statSelect = $('#select-stats');
	
	function ProcessSlices(jquery, length, interval, fn)
	{
		clearTimeout(this.slicesCallback);
		this.slicesCallback = undefined;
		if (jquery.length == 0)
			return;
		
		var context = this;
		var cur = jquery.slice(0, length);
		var next = jquery.slice(length);
		cur.each(fn);
		
		this.slicesCallback = setTimeout(function() { ProcessSlices(next, length, interval, fn); }, interval);
	}
	
	function Debounce(fn, timeout)
	{
		var callback;
		return function() {
			var context = this;
			var args = arguments;
			var doNow = function() {
				fn.apply(context, args);
				callback = undefined;
			};
			clearTimeout(callback);
			callback = setTimeout(doNow, timeout);
		};
	}
	
	function ApplyHighlight()
	{
		var commitInfo = commits[this.dataset.cidx];
		var date = new Date(commitInfo.timestamp * 1000);
		var authorId = commitInfo.authorId;
		var commitId = commitInfo.cid;
		var highlightedCommitId = (highlightedCommit != undefined ? highlightedCommit.cid : undefined)
		var groupId = this.parentElement.dataset.groupid;
		
		var dateOkay = highlightMode == 'commit' || date >= dateFrom && date <= dateTo;
		var authorOkay = selectedAuthorId == undefined || authorId == selectedAuthorId;
		var commitOkay = highlightMode != 'commit' || commitId == highlightedCommitId;
		var groupOkay = highlightMode == 'commit' || (selectedGroupId == 'overall' || groupId == selectedGroupId);
		var allOkay = dateOkay && authorOkay && commitOkay && groupOkay;
		
		$(this).removeClass('color-fade color-highlight color-age color-year color-pretty');
		if (!allOkay)
			$(this).addClass('color-fade');
		if (highlightMode == 'age')
			$(this).addClass('color-age')
	}
	
	function SetupAgeColors() {
		var oldest = commits.reduce(function(x, y) { return (x.timestamp > y.timestamp ? x : y) });
		var newest = commits.reduce(function(x, y) { return (x.timestamp < y.timestamp ? x : y) });
		var base = oldest.timestamp;
		var range = newest.timestamp - oldest.timestamp;
		
		$spans.each(function() {
			var commitInfo = commits[this.dataset.cidx]
			var t = (commitInfo.timestamp - base) / range;
			var tInv = 1.0 - t;
			var hue = 0 - Math.min(120 * t * 2, 120);
			var saturation = 1 - Math.max(t - 0.5, 0) * 2;
			var luminosity = 0.5 + (Math.max(t - 0.5, 0) * 0.3);
			this.style.setProperty('--age-hue', hue);
			this.style.setProperty('--age-sat', saturation * 100 + '%');
			this.style.setProperty('--age-lum', luminosity * 100 + '%');
		});
		
		ageSetupDone = true;
	}
	
	
	
	function UpdateHighlight() {
		$spans.each(ApplyHighlight);
		
		RenderMinimap();
	}
	
	function RenderMinimap() {
		var canvas = document.getElementById("minimap-image");
		canvas.width = $(canvas).width();
		canvas.height = $(canvas).height();
		
		var ctx = canvas.getContext("2d");
		ctx.clearRect(0, 0, canvas.width, canvas.height);
		ctx.setTransform(canvas.width / $content.width(), 0, 0, canvas.height / $content.height(), 0, 0);
		
		var unitX = $content.width() / canvas.width;
		var tabSize = $content.css("tab-size");
		var content = $content.get(0);
		var baseTop = content.offsetTop;
		var baseLeft = content.offsetLeft;
		ProcessSlices($spans, 500, 50, function(i, span) {
			var s = $(span);
			var startTop = span.offsetTop - baseTop;
			var startLeft = span.offsetLeft - baseLeft;
			var text = s.text();
			var lines = text.split("\n");
			var lineHeight = 15;
			var left = startLeft;
			
			ctx.font = $content.css("font-size") + " " + $content.css("font-family");
			ctx.fillStyle = s.css("color");
			for (var j = 0; j < lines.length; ++j) {
				var line = lines[j].replace("\t", " ".repeat(tabSize));
				var top = startTop + j * lineHeight;
				var left = (j == 0 ? startLeft : 0);
				var parts = line.split(/(\s{4,})/);
				for (var k = 0; k < parts.length; ++k)
				{
					var txt = parts[k];
					var width = Math.max(ctx.measureText(txt).width, unitX);
					if (parts[k].trim() != "")
						ctx.fillRect(left, top, width, lineHeight);
					
					if (txt != "")
						left += width;
				}
			}
		});
	}
	
	function UpdateMinimapViewPosition()
	{
		var areaTop = $document.scrollTop() - $content.offset().top + $navbar.height();
		var areaHeight = $content.height();
		var mapHeight = $minimap.height();
		var mapTop = (areaTop / areaHeight) * mapHeight;
		$minimapView.css('top', Math.max(mapTop, 0));
	}
	
	function UpdateMinimapViewSize()
	{
		var viewHeight = $window.innerHeight() - $navbar.height();
		var docHeight = $content.height();
		var mapHeight = $minimap.height();
		var mapViewHeight = (viewHeight / docHeight) * mapHeight;
		$minimapView.css('height', mapViewHeight);
	}
	
	function ShowCommitInfo(commitInfo, clicked) {
		var authorId = commitInfo.authorId;
		var authorName = authors[authorId].name;
		var cid = commitInfo.cid;
		var date = new Date(commitInfo.timestamp * 1000);
		var summary = commitInfo.summary;
		var styleClass = "author-label author" + authorId;
		
		show_commit_popup(cid, authorName, date, summary, styleClass, clicked);
	}
	
	function HideCommitInfo() {
		hide_commit_popup();
	}
	
	function SortContributors(column, reverse)
	{
		var cmp = function(a, b) { if (a < b) return -1; if (a > b) return 1; return 0; };
		var lexical = function (a, b) { return a.children[0].firstChild.innerHTML.localeCompare(b.children[0].firstChild.innerHTML); };
		var numeric = function (a, b) { return cmp(parseFloat(b.children[column].innerHTML), parseFloat(a.children[column].innerHTML)); };
		var numericThenLex = function (a, b) { return numeric(a, b) || lexical(a, b); };
		
		var rows = $contributor_rows.get();
		if (column == 0)
			rows.sort(lexical);
		else
			rows.sort(numericThenLex);
		if (reverse)
			rows.reverse();
		
		$(".table-header-row").after(rows);
	}
	
	function GenerateLineNumbers()
	{
		var text = "";
		for (var i = 1; i <= line_count; ++i)
			text += i + "\n";
		$("#line-numbers").text(text);
	}

	function HighlightSelect_Changed()
	{
		if (guiUpdate)
			return;
		
		var elem = $highlightSelect.get(0);
		var option = elem.options[elem.selectedIndex];
		highlightMode = option.value;
		if (option.id != '')
			selectedAuthorId = option.id;
		else
			selectedAuthorId = undefined;
			
		UpdateHighlight();
	}
	
	function StatSelect_Changed()
	{
		var elem = $statSelect.get(0);
		var index = elem.selectedIndex;
		var stat = stats[index];
		selectedGroupId = elem.value;
		
		var footer = $('.table-footer-row > td');
		var rows = $('.contributor-row');
		footer.get(1).innerHTML = stat.tokens;
		footer.get(3).innerHTML = stat.commits;
		
		var rows = $contributor_rows.get();
		for (var i = 0; i < authors.length; ++i) {
			var id = authors[i].authorId;
			var cells = $(rows[id]).find("td");
			cells.get(0).childNodes[0].innerHTML = authors[i].name;
			cells.get(1).innerHTML = stat.tokens_by_author[i];
			cells.get(2).innerHTML = (stat.tokens_by_author[i] / stat.tokens * 100).toFixed(2) + '%';
			cells.get(3).innerHTML = stat.commits_by_author[i];
			cells.get(4).innerHTML = (stat.commits_by_author[i] / stat.commits * 100).toFixed(2) + '%';
		}
		
		SortContributors(sortColumn, sortReverse);
		UpdateHighlight();
	}
	
	function DateInput_Changed()
	{
		if (guiUpdate)
			return;
		
		dateFrom = document.getElementById("date-from").valueAsDate;
		dateTo = document.getElementById("date-to").valueAsDate;
		dateTo.setDate(dateTo.getDate() + 1)
		var timeStart = dateFrom.getTime() / 1000 - timeMin;
		var timeEnd = dateTo.getTime() / 1000 - timeMin;
		
		guiUpdate = true;
		$( "#date-slider-range" ).slider("values", [timeStart, timeEnd]);
		guiUpdate = false;
		
		UpdateHighlight();
	}
	
	function DateSlider_Changed(event, ui)
	{
		if (guiUpdate)
			return;
		
		var timeStart = timeMin + ui.values[0];
		var timeEnd = timeMin + ui.values[1];
		dateFrom = new Date(timeStart * 1000);
		dateTo = new Date(timeEnd * 1000);
		
		guiUpdate = true;
		$("#date-from").get(0).valueAsDate = dateFrom;
		$("#date-to").get(0).valueAsDate = dateTo;
		guiUpdate = false;
		
		this.UpdateHighlight();
	}
	
	function AuthorLabel_Click(event)
	{
		event.stopPropagation();
		
		var authorId = this.dataset.authorid;
		highlightMode = 'author-single';
		selectedAuthorId = authorId;
		
		var elem = $highlightSelect.get(0);
		var options = elem.options;
		var option = options.namedItem(authorId);
		
		guiUpdate = true;
		elem.selectedIndex = option.index;
		guiUpdate = false;
		
		UpdateHighlight();
	}
	
	function ColumnHeader_Click(event)
	{
		event.stopPropagation();
		
		var column = Array.prototype.indexOf.call(this.parentNode.children, this);
		sortReverse = !sortReverse && (column == sortColumn);
		sortColumn = column;
		
		SortContributors(sortColumn, sortReverse);
	}
	
	function CregitSpan_MouseOver(event)
	{
		event.stopPropagation();
		if (selectedCommit != undefined)
			return;
		
		highlightedCommit = commits[this.dataset.cidx]
		ShowCommitInfo(highlightedCommit, false);
		
		if (line_count > 5000)
			return; // Disable hot tracking on large source files.
		if (highlightMode == 'commit')
			UpdateHighlight();
	}
	
	function CregitSpan_Click(event)
	{
		event.stopPropagation();
		if (selectedCommit == commits[this.dataset.cidx])
			return;
		
		selectedCommit = commits[this.dataset.cidx];
		highlightedCommit = commits[this.dataset.cidx];
		ShowCommitInfo(selectedCommit, true);
		
		if (highlightMode == 'commit')
			UpdateHighlight();
	}
	
	function SourceContent_MouseOver()
	{
		if (selectedCommit != undefined)
			return;
		
		highlightedCommit = undefined;
		HideCommitInfo();
		
		if (highlightMode == 'commit')
			UpdateHighlight();
	}
	
	function SourceContent_MouseLeave()
	{
		if (selectedCommit != undefined)
			return;
		
		HideCommitInfo();
			
		if (highlightMode == 'commit')
			UpdateHighlight();
	}
	
	function MainContent_Click()
	{
		if (selectedCommit == undefined)
			return;
		
		selectedCommit = undefined;
		highlightedCommit = undefined;
		HideCommitInfo();
		
		if (highlightMode == 'commit')
			UpdateHighlight();
	}
	
	function ContextMenuCopy_Click(itemKey, opt)
	{
		var cid = selectedCommit.cid
		var $temp =  $("<textarea>");
        $("body").append($temp);
        $temp.val(cid).select();
        document.execCommand("copy");
        $temp.remove();
	}
	
	function ContextMenuGithub_Click(itemKey, opt)
	{
		var location = new URL(git_url)
		var url = location.toString() + "/commit/" + selectedCommit.cid;
		
		window.open(url, "cregit-window");
	}
	
	function Window_Scroll()
	{
		UpdateMinimapViewPosition();
	}
	
	function Window_Resize()
	{
		UpdateMinimapViewPosition();
		UpdateMinimapViewSize();
		RenderMinimap();
	}
	
	$contributor_headers.click(ColumnHeader_Click);
	
	$spans.mouseover(CregitSpan_MouseOver);
	$spans.click(CregitSpan_Click);
	
	$content.mouseover(SourceContent_MouseOver);
	$content.mouseleave(SourceContent_MouseLeave);
	
	$("#main-content").click(MainContent_Click);

	$highlightSelect.change(HighlightSelect_Changed);
	$highlightSelect.ready(HighlightSelect_Changed);
	
	$statSelect.change(StatSelect_Changed);
	
	$("#date-from").change(DateInput_Changed);
	$("#date-to").change(DateInput_Changed);
	
	$("#date-from").get(0).valueAsDate = dateFrom;
	$("#date-to").get(0).valueAsDate = dateTo;
	
	$(".table-author").click(AuthorLabel_Click);
	
	$("#date-slider-range").get(0).UpdateHighlight = Debounce(UpdateHighlight, 75);
	$("#date-slider-range").slider({range: true, min: 0, max: timeRange, values: [ 0, timeRange ], slide: DateSlider_Changed });
	
	$(window).scroll(Window_Scroll);
	$(window).resize(Debounce(Window_Resize, 250));
	
	UpdateMinimapViewSize();
	GenerateLineNumbers();
	SetupAgeColors();
	initialize_commit_popup(git_url);
});