$(document).ready(function() {
	
	var timeMin = commits[0].timestamp;
	var timeMax = commits[commits.length - 1].timestamp;
	var timeRange = timeMax - timeMin;
	
	var highlightMode = 'author';
	var selectedAuthorId = undefined;
	var selectedCommit = undefined;
	var highlightedCommit = undefined;
	var dateFrom = new Date(timeMin * 1000);
	var dateTo = new Date(timeMax * 1000);
	
	var guiUpdate = false;
	var sortColumn = 1;
	var sortReverse = false;
	var scrollDrag = false;
	
	var $window = $(window);
	var $document = $(document);
	var $minimap = $('#minimap');
	var $spans = $('.cregit-span');
	var $minimapView = $('#minimap-view-shade,#minimap-view-frame');
	var $navbar = $('#navbar');
	var $contributor_rows = $("#stats-table > tbody > tr");
	var $contributor_header_row = $("#stats-table > thead > tr");
	var $contributor_headers = $("#stats-table > thead > tr > th");
	var $contributor_footers = $("#stats-table > tfoot > tr > td");
	var $contributor_row_container = $("#stats-table > tbody");
	var $highlightSelect = $('#select-highlighting');
	var $statSelect = $('#select-stats');
	var $content_groups = $(".content-group");
	var $sourceView = $('#source-view');
	var $content = $('#source-content');
	var $lineNumbers = $("#line-numbers");
	var $lineAnchors = undefined;
	var $mainContent = $("#main-content");
	var $dateGradient = $("#date-gradient");
	var $dateSliderRange = $("#date-slider-range");
	
	// Processes large jquery objects in slices of N=length at rest intervals of I=interval (ms)
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
	
	// Filter callback invocations until no invocations have been made for T=timeout (ms)
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
		var allOkay = dateOkay && authorOkay && commitOkay;
		
		$(this).removeClass('color-fade color-highlight color-age color-year color-pretty');
		if (!allOkay)
			$(this).addClass('color-fade');
		if (highlightMode == 'age')
			$(this).addClass('color-age')
	}
	
	function SetupAgeColors() {
		var oldest = commits.reduce(function(x, y) { return (x.timestamp < y.timestamp ? x : y) });
		var newest = commits.reduce(function(x, y) { return (x.timestamp > y.timestamp ? x : y) });
		var base = oldest.timestamp;
		var range = newest.timestamp - oldest.timestamp;
		
		function convert(color) {
			var canvas = document.createElement("canvas");
			var context = canvas.getContext("2d");
			context.fillStyle = color;
			return parseInt(context.fillStyle.substr(1), 16);
		}
		
		function lerp(c1, c2, t) {
			var r = (c1 & 0xFF0000) * (1 - t) + (c2 & 0xFF0000) * t;
			var g = (c1 & 0x00FF00) * (1 - t) + (c2 & 0x00FF00) * t;
			var b = (c1 & 0x0000FF) * (1 - t) + (c2 & 0x0000FF) * t;
			return (r & 0xFF0000) | (g & 0x00FF00) | (b & 0x0000FF);
		}
		
		var root = $(":root");
		var ageOld = convert(root.css("--age-old"));
		var ageMid = convert(root.css("--age-mid"));
		var ageNew = convert(root.css("--age-new"));
		
		$spans.each(function() {
			var commitInfo = commits[this.dataset.cidx]
			var t = (commitInfo.timestamp - base) / range;
			var color = (t < 0.5 ? lerp(ageOld, ageMid, 0) : lerp(ageMid, ageNew, (t - 0.5) / 0.5));
			var htmlColor = "#" + ("000000" + color.toString(16)).substr(-6);

			this.style.setProperty('--age-color', htmlColor);
		});
		
		ageSetupDone = true;
	}
	
	function UpdateHighlight() {
		$spans.each(ApplyHighlight);
		
		RenderMinimap();
	}
	
	function UpdateVisibility(groupId, lineStart, lineEnd) {
		 // Prevent reflows.
		$content.detach();
		$lineNumbers.detach();
		
		$content_groups.each(function() {
			if (groupId == "overall" || groupId == this.dataset.groupid)
				$(this).removeClass("hidden");
			else
				$(this).addClass("hidden");
		});
		
		$lineAnchors.each(function(i) {
			var number = i + 1;
			if (number >= lineStart && number <= lineEnd)
				$(this).removeClass("hidden");
			else
				$(this).addClass("hidden");
		});
		
		$sourceView.append($lineNumbers);
		$sourceView.append($content);
		
		RenderMinimap();
	}
	
	function ResetHighlightMode() {
		var highlightSelect = $highlightSelect.get(0);
		var statSelect = $statSelect.get(0);
		var date_from = $("#date-from").get(0)
		var date_to = $("#date-to").get(0);
		
		// Reset highlighting parameters
		highlightMode = 'author'
		selectedAuthorId = undefined;
		selectedCommit = undefined;
		highlightedCommit = undefined;
		dateFrom = new Date(timeMin * 1000);
		dateTo = new Date(timeMax * 1000);
		
		// Reset gui elements
		guiUpdate = true;
		highlightSelect.value = "author";
		date_from.valueAsDate = dateFrom;
		date_to.valueAsDate = dateTo;
		$dateSliderRange.slider("values", [0, timeRange]);
		guiUpdate = false;
		$dateGradient.addClass("invisible");
		
		// Update visuals
		HideCommitInfo();
		UpdateHighlight();
	}
	
	function RenderMinimap() {
		var canvas = document.getElementById("minimap-image");
		canvas.width = $(canvas).width();
		canvas.height = $(canvas).height();
		
		var ctx = canvas.getContext("2d");
		ctx.clearRect(0, 0, canvas.width, canvas.height);
		ctx.setTransform(canvas.width / $content.width(), 0, 0, canvas.height / $content.height(), 0, 0);
		
		
		var scrollVisible = $mainContent.get(0).scrollHeight > $mainContent.get(0).clientHeight;
		if (!scrollVisible) {
			$minimapView.addClass("hidden");
			return;
		}
		$minimapView.removeClass("hidden");
		
		var unitX = $content.width() / canvas.width;
		var tabSize = $content.css("tab-size");
		var content = $content.get(0);
		var baseTop = content.offsetTop;
		var baseLeft = content.offsetLeft;
		ProcessSlices($spans, 500, 50, function(i, span) {
			var s = $(span);
			if (s.is(":hidden"))
				return;
			
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
		
		UpdateMinimapViewPosition();
		UpdateMinimapViewSize();
	}
	
	function UpdateMinimapViewPosition()
	{
		var areaY = -$content.position().top;
		var areaHeight = $content.height();
		var mapHeight = $minimap.height();
		var mapYMax = (areaHeight - $mainContent.height()) / areaHeight * mapHeight;
		var mapY = (areaY / areaHeight) * mapHeight;
		
		$minimapView.css('top', Math.max(0, Math.min(mapY, mapYMax)));
	}
	
	function UpdateMinimapViewSize()
	{
		var viewHeight = $mainContent.innerHeight();
		var docHeight = $content.height();
		var mapHeight = $minimap.height();
		var mapViewHeightMax = $minimap.height()
		var mapViewHeight = (viewHeight / docHeight) * mapHeight;
		
		$minimapView.css('height', Math.min(mapViewHeight, mapViewHeightMax));
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
		
		var $rows = $contributor_rows;
		var rows = $contributor_rows.get();
		rows = rows.filter(function(x, i) { return !$(x).hasClass("innactive-row"); });
		
		if (column == 0)
			rows.sort(lexical);
		else
			rows.sort(numericThenLex);
		if (reverse)
			rows.reverse();
		
		// Pad up to 6 rows using the longest name for visual stability.
		while (rows.length < Math.min(6, $rows.length))
			rows.push($("<tr class='contributor-row'><td>&nbsp</td><td/><td/><td/><td/></tr>").get(0));
		
		$rows.detach(); // Detach before empty so rows don't get deleted
		$contributor_row_container.empty();
		$contributor_row_container.append(rows);
	}
	
	function UpdateContributionStats(stat)
	{
		var countHeader = $('#contributor-count');
		var footers = $contributor_footers;
		var rows = $contributor_rows;
		footers.get(1).innerHTML = stat.tokens;
		footers.get(3).innerHTML = stat.commits;
		
		var active_authors = 0;
		var rows = $contributor_rows.get();
		for (var i = 0; i < authors.length; ++i) {
			var id = authors[i].authorId;
			var row = $(rows[id]);
			var cells = row.find("td");
			cells.get(0).childNodes[0].innerHTML = authors[i].name;
			cells.get(1).innerHTML = stat.tokens_by_author[i];
			cells.get(2).innerHTML = (stat.tokens_by_author[i] / stat.tokens * 100).toFixed(2) + '%';
			cells.get(3).innerHTML = stat.commits_by_author[i];
			cells.get(4).innerHTML = (stat.commits_by_author[i] / stat.commits * 100).toFixed(2) + '%';
			
			if (stat.tokens_by_author[i] > 0) {
				row.removeClass("innactive-row");
				active_authors++;
			} else {
				row.addClass("innactive-row");
			}
		}
		
		countHeader.text(active_authors);
		
		SortContributors(sortColumn, sortReverse);
	}
	
	function GenerateLineNumbers()
	{
		// Prevent reflow while adding line anchors
		$lineNumbers.detach();
		var lineNumbers = $lineNumbers.get(0);
		for (var i = 1; i <= line_count; ++i) {
			var a = document.createElement("a");
			a.innerHTML = i;
			a.href = ("#" + i);
			a.className = "line-number";
			lineNumbers.appendChild(a);
		}
		$content.before($lineNumbers);

		$lineAnchors = $lineNumbers.children("a");
	}
	
	function ParseFragmentString()
	{
		var frag = location.hash.substr(1);
		if (frag == "")
			return;
		
		var parts = frag.split(",");
		var line = parseInt(parts[0]);
		var index = Math.min(line, $lineAnchors.length) - 1;
		
		var lineAnchor = $lineAnchors.get(index);
		if(lineAnchor != undefined) {
			var top = lineAnchor.offsetTop - $mainContent.height() / 2;
			$mainContent.stop();
			$mainContent.animate({scrollTop: top}, 200, function(){});
		}
	}
	
	function DoMinimapScroll(event)
	{
		var mouseY = event.clientY;
		var minimapY = mouseY - $minimap.offset().top;
		var contentY = minimapY / $minimap.height() * $content.height();
		var scrollY = $content.get(0).offsetTop + contentY;
		var scrollYMid = scrollY - $mainContent.height() / 2;
		
		$mainContent.scrollTop(scrollYMid);
	}

	function HighlightSelect_Changed()
	{
		if (guiUpdate)
			return;
		
		var elem = $highlightSelect.get(0);
		var option = elem.options[elem.selectedIndex];
		highlightMode = option.value;
		if (highlightMode == 'reset') {
			ResetHighlightMode();
			return;
		}
		
		if (highlightMode == 'age')
			$dateGradient.removeClass("invisible");
		else
			$dateGradient.addClass("invisible");

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
		UpdateContributionStats(stats[index]);
		
		var option = elem.options[elem.selectedIndex];
		var groupId = option.value;
		var lineStart = option.dataset.start;
		var lineEnd = option.dataset.end;
		UpdateVisibility(groupId, lineStart, lineEnd);
		UpdateMinimapViewPosition();
		UpdateMinimapViewSize();
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
		$dateSliderRange.slider("values", [timeStart, timeEnd]);
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
		
		$dateGradient.addClass("invisible");
		
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
	
	function Minimap_MouseDown(event)
	{
		if (event.buttons == 1) {
			scrollDrag = true;
			DoMinimapScroll(event);
		}
	}
	
	function Document_MouseUp(event)
	{
		if (event.buttons == 1)
			scrollDrag = false;
	}
	
	function Document_MouseMove(event)
	{
		if (scrollDrag && event.buttons == 1)
			DoMinimapScroll(event);
		else
			scrollDrag = false;
	}
	
	function Document_SelectStart(event)
	{
		// Disable text selection while dragging the minimap.
		if (scrollDrag)
			event.preventDefault();
	}
	
	function Document_KeyDown(event)
	{
		if (event.key == "Escape")
			ResetHighlightMode();
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
		RenderMinimap();
	}
	
	function Window_HashChange()
	{
		ParseFragmentString();
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
	
	$dateSliderRange.get(0).UpdateHighlight = Debounce(UpdateHighlight, 75);
	$dateSliderRange.slider({range: true, min: 0, max: timeRange, values: [ 0, timeRange ], slide: DateSlider_Changed });
	
	$minimap.mousedown(Minimap_MouseDown);
	$(document).mousemove(Document_MouseMove);
	$(document).mouseup(Document_MouseUp);
	$(document).bind("selectstart", null, Document_SelectStart);
	$(document).keydown(Document_KeyDown);
	
	$mainContent.scroll(Window_Scroll);
	$(window).resize(Debounce(Window_Resize, 250));
	$(window).bind("hashchange", Window_HashChange);
	
	UpdateMinimapViewSize();
	SetupAgeColors();
	
	GenerateLineNumbers();
	ParseFragmentString();
	
	initialize_commit_popup(git_url);
});