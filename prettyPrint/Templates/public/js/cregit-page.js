$(document).ready(function() {
	
	var timeMin = parseInt(commits[0].timestamp);
	var timeMax = parseInt(commits[commits.length - 1].timestamp);
	var timeRange = timeMax - timeMin;
	
	var highlightMode = 'author';
	var selectedAuthorId = undefined;
	var selectedCommit = undefined;
	var highlightedCommit = undefined;
	var dateFrom = new Date(timeMin * 1000);
	var dateTo = new Date(timeMax * 1000);
	
	var guiUpdate = false;
	var lastSortColumn = 1;
	
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
	
	function ApplyHighlight()
	{
		var commitInfo = commits[this.dataset.cidx];
		var date = new Date(commitInfo.timestamp * 1000);
		var authorId = commitInfo.authorId;
		var commitId = commitInfo.cid;
		var highlightedCommitId = (highlightedCommit != undefined ? highlightedCommit.cid : undefined)
		
		var dateOkay = highlightMode == 'commit' || date >= dateFrom && date <= dateTo;
		var authorOkay = selectedAuthorId == undefined || authorId == selectedAuthorId;
		var commitOkay = highlightMode != 'commit' || commitId == highlightedCommitId;
		var allOkay = dateOkay && authorOkay && commitOkay;
		
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
		$spans.removeClass('color-fade color-highlight color-age color-year color-pretty');
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
		
		$spans.each(function(i, span) {
			var s = $(span);
			var left = s.offset().left - $content.offset().left;
			var top = s.offset().top - $content.offset().top;
			var text = s.text();
			var lines = text.split("\n");
			var lineHeight = s.height() / lines.length
			
			ctx.font = "sans-serif";
			ctx.fillStyle = s.css("color");
			for (var j = 0; j < lines.length; ++j)
				ctx.fillRect(left, top + j * lineHeight, ctx.measureText(lines[j]).width, lineHeight);
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
	
	function ShowCommitInfo(commitInfo) {
		var date = new Date(commitInfo.timestamp * 1000);
		var authorId = commitInfo.authorId;
		var authorInfo = authors[authorId];
		$('#commit-hash').text(commitInfo.cid);
		$('#commit-date').text(date.toDateString().substr(4));
		$('#commit-author').text(authorInfo.name);
		$('#commit-author').attr("class", "infotext author-label author" + authorId);
		$('#commit-comment').text(commitInfo.summary);
		$('#commit-info').removeClass('hidden');
		$('#commit-info').stop();
		$('#commit-info').fadeIn(200);
	}
	
	function HideCommitInfo() {
		$('#commit-info').stop();
		$('#commit-info').fadeOut(200, function() {
			$('#commit-info').addClass('hidden');
		});
	}
	
	function SortContributors(column, reverse)
	{
		var rows = $contributor_rows.get();
		if (column == 0)
			rows.sort(function (a, b) { return a.children[0].firstChild.innerHTML.localeCompare(b.children[0].firstChild.innerHTML); });
		else
			rows.sort(function (a, b) { return parseFloat(b.children[column].innerHTML) - parseFloat(a.children[column].innerHTML); });
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
		
		UpdateHighlight();
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
		SortContributors(column, column == lastSortColumn);
		
		lastSortColumn = (column != lastSortColumn ? column : -1);
	}
	
	function CregitSpan_MouseOver(event)
	{
		event.stopPropagation();
		if (selectedCommit != undefined)
			return;
		
		highlightedCommit = commits[this.dataset.cidx]
		ShowCommitInfo(highlightedCommit);
		
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
		ShowCommitInfo(selectedCommit);
		
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
	
	function Window_Scroll()
	{
		UpdateMinimapViewPosition();
	}
	
	function Window_Resize()
	{
		UpdateMinimapViewPosition();
		UpdateMinimapViewSize();
	}
	
	$contributor_headers.click(ColumnHeader_Click);
	
	$spans.mouseover(CregitSpan_MouseOver);
	$spans.click(CregitSpan_Click);
	
	$content.mouseover(SourceContent_MouseOver);
	$content.mouseleave(SourceContent_MouseLeave);
	
	$("#main-content").click(MainContent_Click);

	$highlightSelect.change(HighlightSelect_Changed);
	$highlightSelect.ready(HighlightSelect_Changed);
	
	$("#date-from").change(DateInput_Changed);
	$("#date-to").change(DateInput_Changed);
	
	$("#date-from").get(0).valueAsDate = dateFrom;
	$("#date-to").get(0).valueAsDate = dateTo;
	
	$(".table-author").click(AuthorLabel_Click);
	
	$("#date-slider-range").slider({range: true, min: 0, max: timeRange, values: [ 0, timeRange ], slide: DateSlider_Changed });
	
	$(window).scroll(Window_Scroll);
	$(window).resize(Window_Resize);
	
	UpdateMinimapViewSize();
	GenerateLineNumbers();
	SetupAgeColors();
});