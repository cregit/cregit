$(document).ready(function() {
	
	var $window = $(window);
	var $document = $(document);
	var $minimap = $('#minimap');
	var $spans = $('.cregit-span');
	var $content = $('#source-content');
	var $minimapView = $('#minimap-view-shade,#minimap-view-frame');
	var $navbar = $('#navbar');
	var $contributor_rows = $(".contributor-row");
	var $contributor_headers = $(".table-header-row > th");
	
	var highlightMode = 'author';
	var selectedAuthor = undefined;
	var selectedCommit = undefined;
	var ageSetupDone = false;
	var yearSetupDone = false;
	var showCommitInfo = true;
	var rendering = null;
	var lastSortColumn = 1;
	
	function setup_highlight_age() {
		var oldest = commits.reduce(function(x, y) { return (x.timestamp > y.timestamp ? x : y) });
		var newest = commits.reduce(function(x, y) { return (x.timestamp < y.timestamp ? x : y) });
		var base = oldest.timestamp;
		var range = newest.timestamp - oldest.timestamp;
		
		$spans.each(function() {
			var commitInfo = commits[this.dataset.cidx]
			var t = (commitInfo.timestamp - base) / range;
			var tInv = 1.0 - t;
			var hue = 0 - Math.min(120 * t, 120);
			var saturation = Math.abs(t - 0.5) * 2;
			var luminosity = 0.5 + (Math.max(t - 0.5, 0) * 0.3);
			this.style.setProperty('--age-hue', hue);
			this.style.setProperty('--age-sat', saturation * 100 + '%');
			this.style.setProperty('--age-lum', luminosity * 100 + '%');
		});
		
		ageSetupDone = true;
	}
	
	function setup_highlight_year() {
		var classIdx = 0;
		var yearMap = { };
		commits.forEach(function(val) {
			var year = new Date(val.timestamp * 1000).getYear();
			if (yearMap[year] == undefined)	
				yearMap[year] = 'year' + classIdx++;
		});

		$spans.each(function() {
			var commitInfo = commits[this.dataset.cidx]
			var year = new Date(commitInfo.timestamp * 1000).getYear();
			$(this).addClass(yearMap[year]);
		});
		
		var yearInfo = $('#year-info');
		var years = Object.keys(yearMap);
		years.sort();
		years.forEach(function(val) {
			var legendItem = document.createElement("div");
			var colorBox = document.createElement("div");
			var label = document.createElement("pre");
			legendItem.className = "year-legend-item";
			colorBox.className = "year-legend-box " + yearMap[val];
			label.style = "font-weight: bold; text-align: center";
			label.innerHTML = 1900 + parseInt(val);
			legendItem.appendChild(colorBox);
			legendItem.appendChild(label);
			yearInfo.append(legendItem);
		});
		
		yearSetupDone = true;
	}
	
	function highlight_age() {
		if (!ageSetupDone)
			setup_highlight_age();
		
		$spans.addClass('color-age')
	}
	
	function highlight_year() {
		if (!yearSetupDone)
			setup_highlight_year();
		
		$spans.addClass('color-year')
		
		hide_commit_info();
		show_year_info();
		
		showCommitInfo = false;
	}
	
	function highlight_syntax() {
		$spans.addClass('color-fade color-pretty');
	}
	
	function highlight_date_range() {
		var from = document.getElementById("date-from").valueAsDate;
		var to = document.getElementById("date-to").valueAsDate;		
		$spans.each(function() {
			var commitInfo = commits[this.dataset.cidx];
			var date = new Date(commitInfo.timestamp * 1000);
			if (from == null || to == null)
				$(this).addClass('color-fade');
			else if (date >= from && date <= to)
				$(this).addClass('color-highlight');
			else
				$(this).addClass('color-fade');
		});
	}
	
	function highlight_commit(commit) {
		$spans.each(function() {
			var commitInfo = commits[this.dataset.cidx]
			if (commitInfo != commit)
				$(this).addClass('color-fade');
		});
	}
	
	function highlight_author(authorId) {
		$spans.each(function() {
			var commitInfo = commits[this.dataset.cidx]
			if (commitInfo.authorId != authorId)
				$(this).addClass('color-fade');
		});
	}
	
	function highlight_update() {
		$spans.removeClass('color-fade color-highlight color-age color-year color-pretty');
		if (highlightMode != 'year') {
			hide_year_info();
			showCommitInfo = true;
		}
		
		if (highlightMode == 'author') {
			// Default highlighting
		} else if (highlightMode == 'age') {
			highlight_age();
		} else if (highlightMode == 'year') {
			highlight_date_range();
		} else if (highlightMode == 'syntax') {
			highlight_syntax();
		} else if (highlightMode == 'commit') {
			highlight_commit(selectedCommit);
		} else if (highlightMode == 'author-single') {
			highlight_author(selectedAuthor);
		}
		
		render_minimap();
	}
	
	function highlight_update_commit(commit) {
		if (highlightMode != 'commit')
			return;
		
		$spans.removeClass('color-fade color-age color-pretty');
		highlight_commit(commit);
		render_minimap();
	}
	
	function highlight_update_date_range() {
		if (highlightMode != 'year')
			return;
		
		highlight_update();
	}
	
	function highlight_select()
	{
		var elem = $('#select-highlighting').get(0);
		if (elem.selectedIndex == 0)
			highlightMode = 'author';
		else if (elem.selectedIndex == 1)
			highlightMode = 'age';
		else if (elem.selectedIndex == 2)
			highlightMode = 'year';
		else if (elem.selectedIndex == 3)
			highlightMode = 'commit';
		else
			highlightMode = 'author-single';
		
		if (highlightMode == 'year')
			$("#select-date-range").removeClass("hidden");
		else
			$("#select-date-range").addClass("hidden");
		
		selectedAuthor = elem.value;
		highlight_update();
	}
	
	function show_year_info() {
		$('#year-info').removeClass('hidden');
		$('#year-info').stop();
		$('#year-info').fadeIn(200);
	}
	
	function hide_year_info() {
		$('#year-info').stop();
		$('#year-info').fadeOut(200, function() {
			$('#year-info').addClass('hidden');
		});
	}
	
	function show_commit_info(commitInfo) {
		var date = new Date(commitInfo.timestamp * 1000);
		var authorId = commitInfo.authorId;
		var authorInfo = authors.find(function(x) { return x.authorId == authorId; });
		$('#commit-hash').text(commitInfo.cid);
		$('#commit-date').text(date.toDateString().substr(4));
		$('#commit-author').text(commitInfo.authorId);
		$('#commit-author').attr("class", "infotext author-label " + authorInfo.class);
		$('#commit-comment').text(commitInfo.summary);
		$('#commit-info').removeClass('hidden');
		$('#commit-info').stop();
		$('#commit-info').fadeIn(200);
	}
	
	function hide_commit_info() {
		$('#commit-info').stop();
		$('#commit-info').fadeOut(200, function() {
			$('#commit-info').addClass('hidden');
		});
	}
	
	function render_minimap() {
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
	
	function update_minimap_view_pos()
	{
		var areaTop = $document.scrollTop() - $content.offset().top + $navbar.height();
		var areaHeight = $content.height();
		var mapHeight = $minimap.height();
		var mapTop = (areaTop / areaHeight) * mapHeight;
		$minimapView.css('top', Math.max(mapTop, 0));
	}
	
	function update_minimap_view_size()
	{
		var viewHeight = $window.innerHeight() - $navbar.height();
		var docHeight = $content.height();
		var mapHeight = $minimap.height();
		var mapViewHeight = (viewHeight / docHeight) * mapHeight;
		$minimapView.css('height', mapViewHeight);
	}
	
	function sort_contributors(column, ascending)
	{
		var rows = $contributor_rows.get();
		if (column == 0)
			rows.sort(function (a, b) { return a.children[0].firstChild.innerHTML.localeCompare(b.children[0].firstChild.innerHTML); });
		else
			rows.sort(function (a, b) { return parseFloat(a.children[column].innerHTML) - parseFloat(b.children[column].innerHTML); });
		if (!ascending)
			rows.reverse();
		
		$(".table-header-row").after(rows);
	}
	
	function generate_line_numbers()
	{
		var text = "";
		for (var i = 1; i <= line_count; ++i)
			text += i + "\n";
		$("#line-numbers").text(text);
	}
	
	$contributor_headers.click(function (event) {
		event.stopPropagation();
		
		var column = Array.prototype.indexOf.call(this.parentNode.children, this);
		sort_contributors(column, column != lastSortColumn);
		
		lastSortColumn = (column != lastSortColumn ? column : -1);
	});
	
	$spans.mouseover(function (event) {
		event.stopPropagation();
		
		if (!showCommitInfo)
			return;
		if (selectedCommit != undefined)
			return;
		
		show_commit_info(commits[this.dataset.cidx]);
		highlight_update_commit(commits[this.dataset.cidx]);
	});
	
	$spans.click(function (event) {
		event.stopPropagation();
		
		if (!showCommitInfo)
			return;
		
		selectedCommit = commits[this.dataset.cidx];
		show_commit_info(selectedCommit);
		highlight_update_commit(selectedCommit);
	});
	
	$content.mouseover(function() {
		if (selectedCommit == undefined) {
			hide_commit_info();
			highlight_update_commit(undefined);
		}
	});
	
	$content.click(function() {
		selectedCommit = undefined;
		hide_commit_info();
		highlight_update_commit(undefined);
	});
	
	$content.mouseleave(function() {
		if (selectedCommit == undefined) {
			hide_commit_info();
			highlight_update_commit(undefined);
		}
	});
	
	$(window).scroll(function() {
		update_minimap_view_pos();
	});
	
	$(window).resize(function() {
		update_minimap_view_pos();
		update_minimap_view_size();
	});

	
	$('#select-highlighting').change(highlight_select);
	$('#select-highlighting').ready(highlight_select);
	
	$("#date-from").change(highlight_update_date_range);
	$("#date-to").change(highlight_update_date_range);
	
	var dateFrom = new Date();
	dateFrom.setYear(dateFrom.getFullYear() - 1);
	document.getElementById("date-from").valueAsDate = dateFrom;
	document.getElementById("date-to").valueAsDate = new Date();
	
	update_minimap_view_size();
	generate_line_numbers();
});