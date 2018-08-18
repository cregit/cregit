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
	var $content = $('#source-content');
	var $minimapView = $('#minimap-view-shade,#minimap-view-frame');
	var $navbar = $('#navbar');
	var $contributor_rows = $(".contributor-row");
	var $contributor_headers = $(".table-header-row > th");
	var $highlightSelect = $('#select-highlighting');
	var $statSelect = $('#select-stats');
	var $content_groups = $(".content-group");
	var $lineAnchors = undefined;
	
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
	
	function AdjustForNavbar(yPos)
	{
		return yPos - $navbar.height();
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
	
	function UpdateVisibility(groupId, lineStart, lineEnd) {
		$content_groups.each(function() {
			if (groupId == "overall" || groupId == this.dataset.groupid)
				$(this).removeClass("hidden");
			else
				$(this).addClass("hidden");
		});
		
		$lineAnchors.each(function() {
			var number = parseInt(this.innerHTML);
			if (number >= lineStart && number <= lineEnd)
				$(this).removeClass("hidden");
			else
				$(this).addClass("hidden");
		});
		
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
		statSelect.value = "overall";
		date_from.valueAsDate = dateFrom;
		date_to.valueAsDate = dateTo;
		$( "#date-slider-range" ).slider("values", [0, timeRange]);
		guiUpdate = false;
		
		// Update visuals
		UpdateHighlight();
		UpdateContributionStats(stats[0]);
		UpdateVisibility("overall", 0, line_count);
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
		
		UpdateMinimapViewSize();
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
		var viewHeight = AdjustForNavbar($window.innerHeight());
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
	
	function UpdateContributionStats(stat)
	{
		var countHeader = $('#contributor-count');
		var footer = $('.table-footer-row > td');
		var rows = $('.contributor-row');
		footer.get(1).innerHTML = stat.tokens;
		footer.get(3).innerHTML = stat.commits;
		
		var active_authors = 0;
		var rows = $contributor_rows.get();
		for (var i = 0; i < authors.length; ++i) {
			var id = authors[i].authorId;
			var cells = $(rows[id]).find("td");
			cells.get(0).childNodes[0].innerHTML = authors[i].name;
			cells.get(1).innerHTML = stat.tokens_by_author[i];
			cells.get(2).innerHTML = (stat.tokens_by_author[i] / stat.tokens * 100).toFixed(2) + '%';
			cells.get(3).innerHTML = stat.commits_by_author[i];
			cells.get(4).innerHTML = (stat.commits_by_author[i] / stat.commits * 100).toFixed(2) + '%';
			
			if (stat.tokens_by_author[i] > 0) {
				active_authors++;
				$(cells.get(0).childNodes[0]).removeClass("color-fade");
			} else {
				$(cells.get(0).childNodes[0]).addClass("color-fade");
			}
		}
		
		countHeader.text(active_authors);
		
		SortContributors(sortColumn, sortReverse);
	}
	
	function GenerateLineNumbers()
	{
		var line_numbers = $("#line-numbers")
		
		// Prevent reflow while adding line anchors
		line_numbers.addClass("hidden");
		for (var i = 1; i <= line_count; ++i) {
			var elem = $("<a></a>");
			elem.text(" " + i);
			elem.addClass("line-number");
			elem.attr("href", "#" + i);
			line_numbers.append(elem);
		}
		line_numbers.removeClass("hidden");
		
		$lineAnchors = $(".line-number");
		$lineAnchors.click(LineAnchor_Click);
	}
	
	function ParseFragmentString()
	{
		var frag = location.hash.substr(1);
		if (frag == "")
			return;
		
		var parts = frag.split(",");
		var line = parseInt(parts[0]);
		
		var lineAnchor = $lineAnchors.get(line - 1);
		if(lineAnchor != undefined) {
			var top = AdjustForNavbar(lineAnchor.offsetTop - AdjustForNavbar(window.innerHeight) / 2);
			$(document.documentElement).stop();
			$(document.documentElement).animate({scrollTop: top}, 200, function(){});
		}
	}
	
	function DoMinimapScroll(event)
	{
		var mouseY = event.clientY;
		var minimapY = mouseY - $minimap.get(0).offsetTop;
		var contentY = minimapY / $minimap.height() * $content.height();
		var scrollY = AdjustForNavbar($content.offset().top + contentY);
		var scrollYMid = scrollY - AdjustForNavbar(window.innerHeight) / 2;
		
		document.documentElement.scrollTop = scrollYMid;
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
	
	function LineAnchor_Click(event)
	{
		var top = AdjustForNavbar(this.offsetTop - AdjustForNavbar(window.innerHeight) / 2);
		$(document.documentElement).stop();
		$(document.documentElement).animate({scrollTop: top}, 200, function(){});
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
	
	$minimap.mousedown(Minimap_MouseDown);
	$(document).mousemove(Document_MouseMove);
	$(document).mouseup(Document_MouseUp);
	$(document).bind("selectstart", null, Document_SelectStart);
	$(document).scroll(Window_Scroll);
	
	$(window).resize(Debounce(Window_Resize, 250));
	
	UpdateMinimapViewSize();
	SetupAgeColors();
	
	GenerateLineNumbers();
	UpdateMinimapViewPosition();
	ParseFragmentString();
	
	initialize_commit_popup(git_url);
});