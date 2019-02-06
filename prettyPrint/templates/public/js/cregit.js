document.selectedCid = undefined;
document.selectedRepo = undefined;
document.gitUrl = "";

function windowpop(url) {
    var width = 800;
    var height = 1200;
    var leftPosition = (window.screen.width / 2) - ((width / 2) + 10);
    var topPosition = (window.screen.height / 2) - ((height / 2) + 50);
    
    window.open(url, "cregit", "status=no,height=" + height + ",width=" + width + ",resizable=yes,left=" + leftPosition + ",top=" + topPosition + ",screenX=" + leftPosition + ",screenY=" + topPosition);
}

function menu_copy(itemKey, opt)
{
	var cid = document.selectedCid;
	var $temp =  $("<textarea>");
	$("body").append($temp);
	$temp.val(cid).select();
	document.execCommand("copy");
	$temp.remove();
}

function menu_github(itemKey, opt)
{
    var base = document.selectedRepo;
    if (base == "") {
      base = document.gitUrl;
    }
          
	var cid = document.selectedCid;
	var location = new URL(base)
	var url = location.toString() + "/commit/" + cid;
	
	windowpop(url);
}	

function initialize_commit_popup(gitUrl)
{
	var popupHTML = "".concat(
	"<div id='commit-info' class='commit-info layout-infobox hidden'>",
    "  <span style='font-weight:bold;' class='infotext'>Commit:</span>",
    "  <a id='commit-hash' class='infotext' href='#'></a>",
    "  <span id='commit-author' class='infotext'></span>",
    "  <span id='commit-date' class='infotext'></span>",
    "  <span id='commit-comment' class='summaryBox'></span>",
    "</div>");
	
	var menuItems =
	{
		"copy": { name: "Copy", icon: "copy", callback: menu_copy },
		"sep1": "---------",
		"github": { name: "View on Github", callback: menu_github },
	}
	
	var $container =  $("<div>");
	$container.html(popupHTML);
	$(document.body).append($container);
	$.contextMenu({ selector: '#commit-hash', trigger: 'left', items: menuItems });
	
	document.gitUrl = gitUrl;
}

function show_commit_popup(cid, author, date, summary, repo, styleClasses, clicked)
{
	$('#commit-hash').text(cid);
	$('#commit-date').text(date.toDateString().substr(4));
	$('#commit-author').text(author);
	$('#commit-author').attr("class", "infotext " + styleClasses);
	$('#commit-comment').text(summary);
	$('#commit-info').removeClass('hidden');
	$('#commit-info').stop();
	$('#commit-info').fadeIn(200);
	
	document.selectedCid = cid;
        document.selectedRepo = repo;

}

function hide_commit_popup()
{
	$('#commit-info').stop();
	$('#commit-info').fadeOut(200, function() {
		$('#commit-info').addClass('hidden');
	});
}