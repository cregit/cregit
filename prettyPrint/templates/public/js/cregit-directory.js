$(document).ready(function() {

	$(".content-stats-graph").click(function() {
		var contentGraph = $(this);
		contentDetail = contentGraph.parents("#content-list").next("div");
		contentDetail.slideToggle();
		RepeatFunctionInTimeN(RenderMinimap, 500, 500);
	});

	$("#abs-prop-toggle").click(function() {
		if ($(this).text() == "change scale") { $(this).removeAttr("title"); }
		if ($(this).hasClass("active")) {
			$(this).text("proportional scale");
			$("button.content-stats-graph").each(function() {
				$(this).removeClass("abs-toggle");
			});
		} else {
			$(this).text("absolute scale");
			$("button.content-stats-graph").each(function() {
				$(this).addClass("abs-toggle");
			});
		}

		$(this).toggleClass("active");
		RepeatFunctionInTimeN(RenderMinimap, 500, 500);
	});

	$(".graph-table-data").mouseenter(function() {
		if ($("#abs-prop-toggle").hasClass("active")) { return; }
		$(this).children().addClass("full-scale");
	}); 

	$(".graph-table-data").mouseleave(function() {
		if ($("#abs-prop-toggle").hasClass("active")) { return; }
		$(this).children().removeClass("full-scale");
	}); 

	$("#hide-subdirectory-btn").click(function() {
		$("#subdirectory-list").slideToggle();
		var statsGraphInFileList = $(".content-stats-graph.file-list");
		var close = $(this).text() == "\u2212";

		if (close) {
			statsGraphInFileList.each(function() {
				var width = $(this).data("fileWidth");
				$(this).css("width", width);
			});	
			$(this).text("+");
			$(this).prop("title", "show subdirectories to see relationship between the files and subdirectories");
		} else {
			statsGraphInFileList.each(function() {
				var width = $(this).data("contentWidth");
				$(this).css("width", width);
			});	
			$(this).text("\u2212");
			$(this).prop("title", "hide subdirectories to see relationship between each file");
		}
		
		RepeatFunctionInTimeN(RenderMinimap, 500, 500);
	});

	$("button#expand-stats-table-btn").click(function() {
		$("tr.contributor-row.hidden").each(function() {
			$(this).removeClass("hidden");
		});
		$(this).parent().addClass("hidden");
	});

	var timeRange;
	var highlightMode = 'author';
	var selectedAuthorId = undefined;
	var selectedCommit = undefined;
	var highlightedCommit = undefined;
	var dateFrom = new Date(timeMin * 1000);
	var dateTo = new Date(timeMax * 1000);
	var spanGroupData = undefined;
	
	var guiUpdate = false;
	var sortColumn = 1;
	var sortReverse = false;
	var scrollDrag = false;
	
	var $window = $(window);
	var $document = $(document);
	var $minimap = $('#minimap');
	var $spans = $('.content-stats-graph');
	var $minimapView = $('#minimap-view-shade,#minimap-view-frame');
	var $navbar = $('#navbar');
	var $contributor_rows = $("#stats-table > tbody > tr");
	var $contributor_header_row = $("#stats-table > thead > tr");
	var $contributor_headers = $("#stats-table > thead > tr > th");
	var $contributor_footers = $("#stats-table > tfoot > tr > td");
	var $contributor_row_container = $("#stats-table > tbody");
	var $highlightSelect = $('#select-highlighting');
	var $content_groups = $(".content-group");
	var $sourceView = $('#source-view');
	var $content = $($('#stats-view').get(0));
	var $lineNumbers = $("#line-numbers");
	var $lineAnchors = undefined;
	var $mainContent = $("#main-content");
	var $dateGradient = $("#date-gradient");
	var $dateSliderRange = $("#date-slider-range");



	function RepeatFunctionInTimeN(fn, interval, freq) {
		interval = interval < 0 ? 1000 : interval;
		freq = freq < 0 ? 500 : freq;

		var timerId = setInterval(fn, freq);

		setTimeout(function() {
			clearInterval(timerId);
		}, interval);

	}	

	// Processes large jquery objects in slices of N=length at rest intervals of I=interval (ms)
	function ProcessSlices(jquery, length, interval, fn)
	{
		clearTimeout(this.slicesCallback);
		this.slicesCallback = undefined;
		if (jquery.length == 0) // if no element in the jquery object: return
			return;
		
		var context = this;
		var cur = jquery.slice(0, length); // reduce the set of elements
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
	
	function ApplyHighlight() {
		var dataScript = $(this).children("#data-script");
		eval(dataScript.html());
		var authorId;
		var tokenCount;
		
		function groupMatch(dateGroup) {
			var timestamp = dateGroup.timestamp;
			var group = dateGroup.group;
			var date = new Date(timestamp * 1000);
			var dateOkay = date >= dateFrom && date <= dateTo;
			var authorOkay = group.find(function(authorToken) {
				return authorToken.author_id == authorId;
			});
			return dateOkay && (undefined != authorOkay);
		}

		function getSpanLengthInPercentage(jquery) {
			var authorId = jquery.data("aid");
			var totalTokens = jquery.data("totalTokens");

			var matchedGroup = spanGroupData.filter(groupMatch);

			tokenCount = 0;
			matchedGroup.forEach(function(dateGroup) {
				var authorToken = dateGroup.group.find(function(authorToken) {
					return authorToken.author_id == authorId;
				});
				tokenCount += authorToken.token_count;
			});
			
			return tokenCount/totalTokens; 
		}

		var spanGroup = $(this).children();
		spanGroup.each(function() {
			var colorSpan = $(this);
			if (colorSpan.hasClass("hidden")) { return; }

			authorId = colorSpan.data("aid");
			var spanLenPercentage = parseFloat(colorSpan.data("widthPercent"));
			var newLenPercentage = getSpanLengthInPercentage(colorSpan);
			spanLenPercentage = spanLenPercentage * newLenPercentage;
			colorSpan.css("width", spanLenPercentage+"%");
			var authorName = colorSpan.text();
			colorSpan.prop("title", authorName+" : "+tokenCount+" token(s)");

			var authorOkay = selectedAuthorId == undefined || authorId == selectedAuthorId;
			var allOkay = authorOkay;

			colorSpan.removeClass('color-graph-fade color-highlight color-age color-year color-pretty');
			if (!allOkay) { colorSpan.addClass("color-graph-fade"); }
		});
	}
	
	function SetupAgeColors() {
		var oldest = commits.reduce(function(x, y) { return (x.timestamp < y.timestamp ? x : y); });
		var newest = commits.reduce(function(x, y) { return (x.timestamp > y.timestamp ? x : y); });
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
			// var commitInfo = commits[this.dataset.cidx];
			// var t = (commitInfo.timestamp - base) / range;
			// var color = (t < 0.5 ? lerp(ageOld, ageMid, 0) : lerp(ageMid, ageNew, (t - 0.5) / 0.5));
			// var htmlColor = "#" + ("000000" + color.toString(16)).substr(-6);

			// this.style.setProperty('--age-color', htmlColor);
		});
		
		ageSetupDone = true;
	}
	
	function UpdateHighlight() {
		$spans.each(ApplyHighlight);
		
		// RepeatFunctionInTimeN(RenderMinimap, 500, 50);
		RenderMinimap();
	}
	
	function ResetHighlightMode() {
		var highlightSelect = $highlightSelect.get(0);
		var date_from = $("#date-from").get(0);
		var date_to = $("#date-to").get(0);
		
		// Reset highlighting parameters
		highlightMode = 'author';
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
		UpdateHighlight();
	}
	
	function RenderMinimap() {
		var canvas = document.getElementById("minimap-image");
		canvas.width = $(canvas).width();
		canvas.height = $(canvas).height();
		
		var ctx = canvas.getContext("2d");
		ctx.clearRect(0, 0, canvas.width, canvas.height);
		ctx.setTransform(canvas.width / $content.width(), 0, 0, canvas.height / $content.height(), 0, 0);
		
		// check if current page needs minimap
		var scrollVisible = $mainContent.get(0).scrollHeight > $mainContent.get(0).clientHeight;
		if (!scrollVisible) {
			$minimapView.addClass("hidden");
			return;
		}
		$minimapView.removeClass("hidden");
		
		var unitX = $content.width() / canvas.width;
		var tabSize = $content.css("tab-size");
		var content = $content.get(0);
		var base = $(content).offset();
		var baseTop = base.top;
		var baseLeft = base.left;
		ProcessSlices($spans, 500, 50, function(i, span) {
			var s = $(span);
			if (s.is(":hidden"))
				return;
			
			var x = s.offset();
			var startTop = x.top - baseTop;
			var startLeft = 0;
			var lineHeight = 15;
			var left = startLeft;
			
			ctx.font = $content.css("font-size") + " " + $content.css("font-family");
			var childrenSpan = s.children();
			childrenSpan.each(function() {
				if ($(this).hasClass("hidden") == true)	{ return; }

				ctx.fillStyle = $(this).css("background-color");
				var width = $(this).width();
				ctx.fillRect(left, startTop, 1.5*width, lineHeight);
				left += 1.5*width;
			});
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
		var mapViewHeightMax = $minimap.height();
		var mapViewHeight = (viewHeight / docHeight) * mapHeight;
		
		$minimapView.css('height', Math.min(mapViewHeight, mapViewHeightMax));
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
	
	function DateInput_Changed()
	{
		if (guiUpdate)
			return;
		
		dateFrom = document.getElementById("date-from").valueAsDate;
		dateFrom = new Date(dateFrom.getFullYear(), dateFrom.getMonth(), 1, 0, 0, 0);
		dateTo = document.getElementById("date-to").valueAsDate;
		dateTo = new Date(dateTo.getFullYear(), dateTo.getMonth(), 1, 0, 0, 0);

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
		// reformat the dateFrom and dateTo to only allows user to change month and year
		var yearFrom = dateFrom.getFullYear();
		var monthFrom = dateFrom.getMonth();
		dateFrom = new Date(yearFrom, monthFrom, 1, 0, 0, 0);

		var yearTo = dateTo.getFullYear();
		var monthTo = dateTo.getMonth();
		dateTo = new Date(yearTo, monthTo, 1, 0, 0, 0);

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

	function UpdateDate() {
		var yearFrom = dateFrom.getFullYear();
		var monthFrom = dateFrom.getMonth();
		dateFrom = new Date(yearFrom, monthFrom, 1, 0, 0, 0);
		timeMin = Math.round(dateFrom.getTime()/1000);

		var yearTo = dateTo.getFullYear();
		var monthTo = dateTo.getMonth();
		dateTo = new Date(yearTo, monthTo+1, 1, 0, 0, 0);
		timeMax = Math.round(dateTo.getTime()/1000);

		timeRange = timeMax - timeMin; 
	}
	
	$contributor_headers.click(ColumnHeader_Click);
	
	$highlightSelect.change(HighlightSelect_Changed);
	$highlightSelect.ready(HighlightSelect_Changed);
	
	$("#date-from").change(DateInput_Changed);
	$("#date-to").change(DateInput_Changed);

	UpdateDate();
	
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
	RenderMinimap();

	// SetupAgeColors();
	
	ParseFragmentString();
});
