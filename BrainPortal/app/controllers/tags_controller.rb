
#
# CBRAIN Project
#
# Controller for tags resource.
#
# Original author: Tarek Sherif
#
# $Id$
#

#RESTful controller for the Tag resource.
class TagsController < ApplicationController

  Revision_info = "$Id$"

  before_filter :login_required
  
  # GET /tags
  # GET /tags.xml
  def index #:nodoc:
    cb_error "Tags 'index' page not available anymore."
  end

  # GET /tags/1
  # GET /tags/1.xml
  def show #:nodoc:
    cb_error "Tags 'show' page not available anymore."
  end

  # GET /tags/1/edit
  def edit #:nodoc:
    @tag = current_user.tags.find(params[:id])
  end

  # POST /tags
  # POST /tags.xml
  def create #:nodoc:
    @tag = Tag.new(params[:tag])
    @tag.user_id = current_user.id

    respond_to do |format|
      if @tag.save
        flash[:notice] = 'Tag was successfully created.'
        format.html { redirect_to userfiles_path }
        format.js {render :partial  => 'shared/create', :locals  => {:model_name  => 'tag' }}
        format.xml  { render :xml => @tag, :status => :created, :location => @tag }
      else
        format.html { redirect_to userfiles_path }
        format.js {render :partial  => 'shared/create', :locals  => {:model_name  => 'tag' }}
        format.xml  { render :xml => @tag.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /tags/1
  # PUT /tags/1.xml
  def update #:nodoc:
    @tag = current_user.tags.find(params[:id])
    tag_name = @tag.name

    respond_to do |format|
      if @tag.update_attributes(params[:tag])
        flash[:notice] = 'Tag was successfully updated.'
        if current_session.userfiles_tag_filters && current_session.userfiles_tag_filters.include?(tag_name)
          current_session.userfiles_tag_filters.delete tag_name
          current_session.userfiles_tag_filters << @tag.name
        end
        format.html { redirect_to userfiles_path }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @tag.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /tags/1
  # DELETE /tags/1.xml
  def destroy #:nodoc:
    @tag = current_user.tags.find(params[:id])
    if current_session.userfiles_tag_filters
      current_session.userfiles_tag_filters.delete @tag.name
    end
    @destroyed = @tag.destroy

    respond_to do |format|
      format.html { redirect_to userfiles_path }
      format.xml  { head :ok }
    end
  end
end
