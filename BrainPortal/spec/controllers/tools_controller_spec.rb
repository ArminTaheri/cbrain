
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.  
#

require 'spec_helper'

describe ToolsController do
  let(:tool) {mock_model(Tool).as_null_object}
  
  context "with a logged in user" do
    context "user is an admin" do
      let(:current_user) {Factory.create(:admin_user)}
      before(:each) do
        session[:user_id] = current_user.id
      end
  
      describe "index", :current => true do
        before(:each) do
          controller.stub(:base_filtered_scope).and_return(double("scope").as_null_object)
          controller.stub(:base_sorted_scope).and_return([tool])
        end
        
        it "should assign @tools" do
          get :index
          assigns[:tools].should == [tool]
        end
        it "should render the index page" do
          get :index
          response.should render_template("index")
        end
      end
  
      describe "bourreau_select" do
        let(:real_tool) {Factory.create(:tool, :user_id => current_user.id )}
  
        it "should render empty text if tool_id is empty" do
          get(:bourreau_select, {'tool_id' => ""})
          response.body.should be_empty
        end
  
        it "should render bourreau_select" do
          get(:bourreau_select,{'tool_id' => real_tool.id.to_s})
          response.should render_template("tools/_bourreau_select")
        end 
        
        it "should display error text if go in rescue" do
          get(:bourreau_select, {'tool_id' => "abc"})
          response.body.should =~ /No Execution Servers/
        end
      end
  
      describe "create" do
        let(:mock_tool) {mock_model(Tool).as_null_object}
        
        it "should autoload_all_tools if autoload is defined" do
          controller.stub!(:render)
          controller.should_receive(:autoload_all_tools)
          post :create, :tool => {}, :autoload => "true", :format => "js"
        end

        context "when save is successful" do
          before(:each) do
            Tool.stub!(:new).and_return(mock_tool)
            mock_tool.stub_chain(:errors, :add)
            mock_tool.stub!(:save).and_return(true)
            mock_tool.stub_chain(:errors, :empty?).and_return(true)
          end
          
          it "should send a flash notice" do
            post :create, :tool => {}
            flash[:notice].should  be_true
          end
          it "should redirect to the index" do
            post(:create, :tool => {:name => "name"}, :format => "js")
            response.should redirect_to(:action => :index, :format => :js)
          end          
        end

        context "when save failed" do
          before(:each) do
            Tool.stub!(:new).and_return(mock_tool)
            mock_tool.stub_chain(:errors, :add)
            mock_tool.stub!(:save).and_return(false)
            mock_tool.stub_chain(:errors, :empty?).and_return(false)
          end
          
          it "should render 'failed create' partial" do
            post(:create, :tool => {:name => "name"},:format => "js")
            response.should render_template("shared/_failed_create")
          end
        end
      
      end
  
      describe "update" do
        let(:real_tool) {Factory.create(:tool, :user_id => current_user.id )}
  
        it "should find available tools" do
          put :update, :id => real_tool.id
          assigns[:tool].should == real_tool
        end
  
        context "when update is successful" do
          it "should display a flash message" do
            put :update, :id => real_tool.id
            flash[:notice].should == "Tool was successfully updated."
          end
        end
  
        context "when update fails" do
          let(:mock_tool) {mock_model(Tool).as_null_object}

          it "should render the edit page" do
            put :update, :id => real_tool.id, :tool => {:name => ""} 
            response.should render_template("edit")
          end
        end
      end
  
      describe "destroy" do
        let(:real_tool) {Factory.create(:tool, :user_id => current_user.id )}
        
        it "should find the requested tag" do
          delete :destroy, :id => real_tool.id
          assigns[:tool].should == real_tool
        end
        it "should allow me to destroy a tool" do
          delete :destroy, :id => real_tool.id
          Tool.all.should_not include(real_tool)
        end
        it "should redirect to the index" do
          delete :destroy, :id => real_tool.id, :format => "js"
          response.should redirect_to(:action => :index, :format => :js)
        end
      end
  
    end

    context "user is a standard user" do
      let(:current_user) {Factory.create(:normal_user)}
      before(:each) do
        session[:user_id] = current_user.id
      end
  
      describe "index" do
        before(:each) do
          controller.stub(:base_filtered_scope).and_return(double("scope").as_null_object)
          controller.stub(:base_sorted_scope).and_return([tool])
        end
  
        it "should assign @tools" do
          get :index
          assigns[:tools].should == [tool]
        end
        it "should render the index page" do
          get :index
          response.should render_template("index")
        end
      end
  
      describe "bourreau_select" do
        let(:real_tool) {Factory.create(:tool, :user_id => current_user.id )}
  
        it "should render empty text if tool_id is empty" do
          get(:bourreau_select, {'tool_id' => ""})
          response.body.should be_empty
        end
  
        it "should render bourreau_select" do
          get(:bourreau_select,{'tool_id' => real_tool.id.to_s})
          response.should render_template("tools/_bourreau_select")
        end 
        
        it "should display error text if go in rescue" do
          get(:bourreau_select, {'tool_id' => "abc"})
          response.body.should =~ /No Execution Servers/
        end
      end
  
      describe "edit" do
  
        it "should redirect to error page" do
          get(:edit, {"id" => "1"})
          response.code.should == '401'
        end
      end
  
      describe "create" do
       
        it "should redirect to error page" do
          post(:create, :tool => {:name => "name"})
          response.code.should == '401'
        end
      
      end
  
      describe "update" do
                
        it "should redirect to error page" do
          put :update, :id => "1"
          response.code.should == '401'
        end
      end
  
      describe "destroy" do
        
        it "should redirect to error page" do
          delete :destroy, :id => "1"
          response.code.should == '401'
        end
      end
  
    end

    context "user is a site_manager" do
      let(:current_user) {Factory.create(:site_manager)}
      before(:each) do
        session[:user_id] = current_user.id
      end
  
      describe "index" do
        before(:each) do
          controller.stub(:base_filtered_scope).and_return(double("scope").as_null_object)
          controller.stub(:base_sorted_scope).and_return([tool])
        end
  
        it "should assign @tools" do
          get :index
          assigns[:tools].should == [tool]
        end
        it "should render the index page" do
          get :index
          response.should render_template("index")
        end
      end
  
      describe "bourreau_select" do
        let(:real_tool) {Factory.create(:tool, :user_id => current_user.id )}
  
        it "should render empty text if tool_id is empty" do
          get(:bourreau_select, {'tool_id' => ""})
          response.body.should be_empty
        end
  
        it "should render bourreau_select" do
          get(:bourreau_select,{'tool_id' => real_tool.id.to_s})
          response.should render_template("tools/_bourreau_select")
        end 
        
        it "should display error text if go in rescue" do
          get(:bourreau_select, {'tool_id' => "abc"})
          response.body.should =~ /No Execution Servers/
        end
      end
  
      describe "edit" do
  
        it "should redirect to error page" do
          get(:edit, {"id" => "1"})
          response.code.should == '401'
        end
      end
  
      describe "create" do
       
        it "should redirect to error page" do
          post(:create, :tool => {:name => "name"})
          response.code.should == '401'
        end
      
      end
  
      describe "update" do
                
        it "should redirect to error page" do
          put :update, :id => "1"
          response.code.should == '401'
        end
      end
  
      describe "destroy" do
        
        it "should redirect to error page" do
          delete :destroy, :id => "1"
          response.code.should == '401'
        end
      end
  
    end
  end

  context "when the user is not logged in" do
    describe "index" do
      it "should redirect the login page" do
        get :index
        response.should redirect_to(:controller => :sessions, :action => :new)
      end
    end
    
    describe "edit" do
      it "should redirect the login page" do
        get :edit, :id => 1
        response.should redirect_to(:controller => :sessions, :action => :new)
      end
    end
    
    describe "create" do
      it "should redirect the login page" do
        post :create
        response.should redirect_to(:controller => :sessions, :action => :new)
      end
    end
    
    describe "update" do
      it "should redirect the login page" do
        put :update, :id => 1
        response.should redirect_to(:controller => :sessions, :action => :new)
      end
    end
    
    describe "destroy" do
      it "should redirect the login page" do
        delete :destroy, :id => 1
        response.should redirect_to(:controller => :sessions, :action => :new)
      end
    end
  end
end

