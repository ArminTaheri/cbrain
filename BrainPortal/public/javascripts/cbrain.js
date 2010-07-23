var macacc;
var brainbrowser;
function set_ajax_elements(){
        jQuery(".ajax_element").each(function (index,element){
    	  //jQuery(element).load(jQuery(element).attr("data-url"));
    	  var url = jQuery(element).attr("data-url");
    	  var error_message = jQuery(element).attr("data-error");
    	  var replace = jQuery(element).attr("data-replace");
    	  jQuery.ajax({
    	    type: 'GET',
    	    url: url,
    	    dataType: 'html',
    	    success: function(data) {
    	      if(replace == "true"){
    	        jQuery(element).replaceWith(data);
    	      }else{
    	        jQuery(element).html(data);
  	        }
    	    },
    	    error: function(e) {
    	      if(!error_message){
    		error_message = "Error loading element";
    	      }
    	      jQuery(element).html("<span>"+ error_message +"</span>");
    	    },
    	    timeout: 50000


	       });
       });
}

jQuery(
  function() {

    set_ajax_elements();
    
    //All elements with the accordion class will be changed to accordions.
    jQuery(".accordion").accordion({
      active: false,
      collapsible: true,
      autoHeight: false}
    );


    //Sortable list of elements
    jQuery(".sortable_list").sortable();
    jQuery(".sortable_list").disableSelection();

    jQuery(".slider_field").each( function() {
      var slider_text_field = jQuery(this).children().filter("input");
      jQuery(this).children().filter(".slider").slider({ change: function(event,ui) {
        jQuery(slider_text_field).val(ui.value);
        }});


      });

      jQuery(".draggable_element").draggable({
        connectToSortable: '#sortable',
        helper: 'clone',
        revert: 'invalid'


      });
      jQuery(".sortable_list ul, sortable_list li").disableSelection();

      //Tab Bar, div's of type tabs become tab_bars
      jQuery(".tabs").tabs();

      //Overlay dialogs
    jQuery(".overlay_dialog").each( function(index,element){
      var content_width = parseInt(jQuery(element).children('.dialog').attr('data-width'));
      var dialog = jQuery(this).children(".dialog")
      dialog.remove().appendTo("body");
      
      dialog.dialog({ autoOpen: false,
          modal: true,
          position: "center",
	  resizable: false,
	  width: content_width
	 });

          var button = jQuery(this).children(".dialog_button").click(function(){dialog.dialog('open')});



        });


    jQuery(".overlay_link").click( function() {
      var url=jQuery(this).attr('data-url');
      var dialog = jQuery("<div></div>").load(url).appendTo(jQuery("body")).dialog({
      	show: "puff",
      	modal: true,
	      position: 'center',
      	width: 800,
      	height: 600
      });

    });



        jQuery(".inline_edit_field").each(function() {
          var input_field = jQuery(this).children().filter("span").children().filter("input").hide();
          var save_link = jQuery(this).children().filter(".inplace_edit_field_save").hide();
          var text = jQuery(this).children().filter("span").children().filter(".current_text");
          var save_function = function(event) {
            text.html(input_field.val());
            input_field.hide();
            save_link.hide();
            text.show();
          };
          input_field.change(save_function);

          jQuery(save_link).click(save_function);


          jQuery(this).children().filter("span").click(function(event){
            input_field.val(text.html());
            text.hide();
            input_field.show();
            save_link.show();
          });

        });





        jQuery(".button").button();
        jQuery(".button_with_drop_down").children(".button_menu").button({
          icons: {
            secondary: 'ui-icon-triangle-1-s'
          }



        }).toggle(function(event){
	        var menu = jQuery(this).siblings(".drop_down_menu");
	        jQuery(".drop_down_menu:visible").siblings(".button_menu").click();
      	  menu.show();
        },
        function(event){
      	  var menu = jQuery(this).siblings(".drop_down_menu");
      	  menu.hide();
        });



        jQuery(".button_with_drop_down > div.drop_down_menu").hide();

        jQuery(".ajax_form").live("submit", function(){
          var data_type = jQuery(this).attr("data-datatype");
          var target = jQuery(this).attr("data-target");
          if(!data_type) data_type = "html";
          jQuery(this).ajaxSubmit({
            type: "POST",
            dataType: data_type,
            target: jQuery(target),
            success: function(data){
              jQuery(target).html(data);
            },
            resetForm: true
          });
          return false;
        });
        
        jQuery(".search_box").live("keypress", function(event){ 
          if(event.keyCode == 13){
            text_field = jQuery(this);
            var data_type = text_field.attr("data-datatype");
            if(!data_type) data_type = "script";
            var url = text_field.attr("data-url");
            var method = text_field.attr("data-method");
            if(!method) method = "GET";
            var target = text_field.attr("data-target");
                    
                    
            var parameters = {};
            parameters[text_field.attr("id")] = text_field.attr("value");
          
            jQuery.ajax({ 
              type: method,
              url: url,
              dataType: data_type,
              target: target, 
              data: parameters
            });
            return false;
          }
        });
        
        jQuery(".ajax_submit_button").live("click", function(){
          button = jQuery(this);
          commit = button.attr("value");
          var data_type = button.attr("data-datatype");
          var url = button.attr("data-url");
          var method = button.attr("data-method");
          enclosing_form = button.closest("form");
          if(!data_type) data_type = enclosing_form.attr("data-datatype");
          if(!data_type) data_type = "html";
          
          if(!url) url = enclosing_form.attr("action");
          
          if(!method) method = enclosing_form.attr("data-method");
          if(!method) method = "POST";          
                    
          enclosing_form.ajaxSubmit({
            url: url,
            type: method,
            dataType: data_type,
            data: { commit : commit },
            resetForm: false
            }
          );
          return false;
        });
        
        jQuery(".userfiles_partial_form").live("submit", function(){
          current_form = jQuery(this);
      try{
          var data_type = current_form.attr("data-datatype");
          var target = current_form.attr("data-target");
          var method = current_form.attr("data-method");
          if(!data_type) data_type = "html";
          if(!method) method = "POST";
     
          commit = this.commit.value;
         
             var post_data = { commit : commit, iamjs: "YES" };
              var file_ids = new Array();
              jQuery('.userfiles_checkbox:checked').each(function(index, element){
                file_ids.push(element.value);
              });
            }catch(e){
              alert(e.toString());
              return false;
            }
          post_data["filelist[]"] = file_ids;
          current_form.ajaxSubmit({
            type: method,
            data: post_data,
            dataType: data_type,
            target: target,
            resetForm: true
          });
          
          return false;
        });
        
        jQuery("#jiv_submit").click(function(){
          var data_type = jQuery(this).attr("data-datatype");
          jQuery(this).closest("form").ajaxSubmit({
            url: "/jiv",
            type: "GET",
            resetForm: false,
            success: function(data){
              jQuery("<div id='jiv_option_div'></div>").html(data).appendTo(jQuery("body")).dialog({
              	show: "puff",
              	modal: true,
        	      position: 'center',
              	width: 400,
              	height: 300,
              	close: function(){
              	  jQuery(this).remove();
              	}
              });
            }
          });
          return false;
        });



        function ajax_onclick_show(event) {
          var onclick_elem = jQuery(this);
          var before_content = onclick_elem.attr("data-before");
          var replace_selector = onclick_elem.attr("data-replace");
          var replace_position = onclick_elem.attr("data-position");
          var parents = onclick_elem.attr("data-parents");
          if(!parents){
            parents = ""
          };
          parents += " __cbrain_parent_" + onclick_elem.attr("id");
          if(!replace_selector) {
            var replace_elem = onclick_elem;
          } else {
            var replace_elem=jQuery("#" + replace_selector);
          };
          if(!before_content) {
            before_content = "<span class='loading_message'>Loading...</span>";
          };
          before_content = jQuery(before_content);
          if(replace_position == "after") {
            replace_elem.after(before_content);
          }else if (replace_position == "replace"){
            replace_elem.replaceWith(before_content);
          }else{
            replace_elem.html(before_content);
          }

          onclick_elem.removeClass("ajax_onclick_show_element");
          onclick_elem.unbind('click');
          onclick_elem.addClass("ajax_onclick_hide_element");
          jQuery.ajax({ type: 'GET',
            url: jQuery(onclick_elem).attr("data-url"),
            dataType: 'html',
            success: function(data){
              var new_data = jQuery(data);
              new_data.attr("data-parents", parents);
              new_data.addClass(parents);
              before_content.replaceWith(new_data);
              onclick_elem.find(".ajax_onclick_show_child").hide();
              onclick_elem.find(".ajax_onclick_hide_child").show();
            },
	          error:function(e) {
	            var new_data = jQuery("Error occured while processing this request");
              new_data.attr("data-parents", parents);
              new_data.addClass(parents);
              before_content.replaceWith(new_data);
              onclick_elem.find(".ajax_onclick_show_child").hide();
              onclick_elem.find(".ajax_onclick_hide_child").show();
  	        },
            data: {},
	          async: true,
	          timeout: 50000
          });

      };

      function ajax_onclick_hide(event){
        var onclick_elem = jQuery(this);
        var parental_id = "__cbrain_parent_" + onclick_elem.attr("id");
        jQuery("." + parental_id).remove();
        onclick_elem.removeClass("ajax_onclick_hide_element");
        onclick_elem.unbind('click');
        onclick_elem.addClass("ajax_onclick_show_element");
        onclick_elem.find(".ajax_onclick_hide_child").hide();
        onclick_elem.find(".ajax_onclick_show_child").show();
      };

      jQuery(".ajax_onclick_show_element").live("click", ajax_onclick_show);
      jQuery(".ajax_onclick_hide_element").live("click", ajax_onclick_hide);

      jQuery("table.resource_list").live("mouseout", function() {highlightTableRowVersionA(0); });
      jQuery(".row_highlight").live("hover", function() {highlightTableRowVersionA(this, '#FFEBE5');});

    jQuery(".o3d_link").live('click',o3DOverlay);

    jQuery(".macacc_link").live('click',macaccOverlay);

    function macaccOverlay(event) {


      var macacc=jQuery("<div id=\"macacc_viewer\"></div>").load(jQuery(this).attr('data-viewer')).appendTo(jQuery("body")).dialog({
	show: "puff",
      	modal: true,
	position: 'center',
      	width: 1024,
      	height:  768,
	async: false,
	close: function(){
      	  brainbrowser.uninit();
      	  jQuery("#macacc_viewer").remove();
      	}
      });
      jQuery(".macacc_button").button();
      brainbrowser = new BrainBrowser();
      brainbrowser.afterInit = function(bb) {
	macacc = new MacaccObject(bb,jQuery("#launch_macacc").attr("data-content-url"));
	jQuery('#fillmode').toggle(bb.set_fill_mode_wireframe,bb.set_fill_mode_solid);
	jQuery('#range_change').click(macacc.range_change);
	jQuery('.data_controls').change(macacc.data_control_change);
	macacc.pickInfoElem=jQuery("#vertex_info");
	jQuery('#screenshot').click(function(event) {jQuery(this).attr("href",bb.client.toDataURL());});

      };
      brainbrowser.setup(jQuery("#launch_macacc").attr("data-content-url")+"?model=normal");

      jQuery("#viewinfo > .button").button();

    }



    function o3DOverlay(event) {
      var macacc=jQuery("<div id=\"civet_viewer\"></div>").load(jQuery(this).attr('data-viewer')).appendTo(jQuery("body")).dialog({
     	show: "puff",
      	modal: true,
	position: 'center',
      	width: 1024,
      	height: 768,
      	close: function(){
      	  brainbrowser.uninit();
      	  jQuery("#civet_viewer").remove();
      	}
      });
      brainbrowser = new BrainBrowser();
      var civet;
      var obj_link = this;
      brainbrowser.afterInit = function(bb) {
	civet = new CivetObject(bb,jQuery(obj_link).attr("data-content"));
	jQuery('#fillmode').toggle(bb.set_fill_mode_wireframe,bb.set_fill_mode_solid);
	jQuery('#range_change').click(civet.range_change);
	civet.pickInfoElem=jQuery("#vertex_info");
	jQuery('#screenshot').click(function(event) {jQuery(this).attr("href",bb.client.toDataURL());});
      };
      brainbrowser.setup(jQuery(this).attr('data-content-url'));
      return false;
      };



});


