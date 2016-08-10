#!/usr/bin/env ruby

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

# This rspec file tests the Boutiques framework on the Portal side.
# It uses a test (mock) application to do so.
# This set of tests does the following:
#   (1) Validates the JSON descriptor
#   (2) Tests that the local script behaviour is as expected
#   (3) Tests the generated portal task class (including the after_form method)
#
# The following should be done before testing
#   bundle exec rake db:test:prepare
#   rake db:seed RAILS_ENV=test
# Then run via: rspec spec/boutiques/boutiques_tester_spec.rb --colour


# Helper testing methods
require_relative 'test_helpers'

# Gain access to the rails environment
require 'rails_helper'
require 'spec_helper'

# Add helper methods for performing tests
include TestHelpers

# Run the Boutiques test on the BrainPortal side
describe "BrainPortal Boutiques Tests" do

  # Run before block to create required input files
  before(:all) do
    createInputFiles
  end

  # Post-test cleanup via after block
  after(:all) do
    destroyInputFiles
    destroyOutputFiles
  end

  # Validate correctness of JSON descriptor
  describe "JSON descriptor" do
    it "validates" do
      schemaLoc = File.join(SchemaTaskGenerator::SCHEMA_DIR, SchemaTaskGenerator::DEFAULT_SCHEMA_FILE)
      expect( runAndCheckJsonValidator(schemaLoc) ).to eql(true)
    end
  end

  # Run tests locally on script
  describe "Local script test" do

    # After each local test, destroy the output files
    after(:each) do
      destroyOutputFiles
    end

    # Perform the local tests to make sure the program behaves as expected
    # (especially as it is changed to add new Boutiques features)
    BasicTests.each do |test|
      it "#{test[0]}" do
        expect( runTestScript( test[1], test[3] || [] ) ).to eq( test[2] )
      end
    end

  end

  # Run tests on generated portal tasks based on full mock app
  describe 'Local boutiques task (full mock app):' do

    # Prevent warnings about redefining constants by using a before(:all)
    before(:all) do
      # Mock metadata
      GID, DPID = Group.everyone.id, 9
    end

    # Run before block to create required task and task class
    before(:each) do
      @user          = FactoryGirl.create(:user)
      @UID           = @user.id
      execer         = create(:bourreau)
      schema         = SchemaTaskGenerator.default_schema
      descriptor     = File.join(__dir__, TestScriptDescriptor)
      @boutiquesTask = SchemaTaskGenerator.generate(schema, descriptor)
      @boutiquesTask.integrate if File.exists?(descriptor)
      # Instantiate a task object
      @task          = CbrainTask::BoutiquesTest.new
      @task.bourreau = execer
      @task.user_id, @task.group_id, @task.params = @UID, GID, {}
      # Setup for holding the files the user had selected in the UI
      @task.params[:interface_userfile_ids] = []
      # Create a local data_provider to hold our files
      @provider = FlatDirLocalDataProvider.new({ :online => true, :read_only => false, :remote_dir => '.' })
      @provider.id, @provider.name, @provider.user_id, @provider.group_id = DPID, 'test_provider', @UID, GID
      @provider.save!
      # Helper to create userfiles
      @makeUserfile = -> (name) {
        outfile = SingleFile.new({data_provider_id: DPID, name: name, group_id: GID, user_id: @UID})
        outfile.save!
        @task.params[:interface_userfile_ids] << outfile.id
        outfile
      }
      # Create userfiles for C, d, j, f (used to convert the ids from strings to numbers)
      @file_C, @file_d, @file_j = @makeUserfile.('c'), @makeUserfile.('d'), @makeUserfile.('j')
      @file_f1, @file_f2 = @makeUserfile.('f1'), @makeUserfile.('f2')
      # Helper for converting files in the argument dict to int ids
      @replaceFileIds = -> (replaceF=false) {
        @task.params[:C] = @file_C.id unless @task.params[:C].nil?
        @task.params[:d] = @file_d.id unless @task.params[:d].nil?
        @task.params[:j] = @file_j.id unless @task.params[:j].nil?
        @task.params[:f] = [ @file_f1.id, @file_f2.id ] if replaceF
      }
      # Give access to the class version of the task
      @task_const = "CbrainTask::#{SchemaTaskGenerator.classify(@task.name)}".constantize
    end

    # Test the object generated by the Boutiques generator
    context "Boutiques GeneratedTask Object" do
      it "should have the right name" do
        expect( @boutiquesTask.name ).to eq( "BoutiquesTest" )
      end
      it "should have no validation errors" do
        expect( @boutiquesTask.validation_errors ).to be true
      end
    end

    # Test the portal class automatically generated and registered in cbrain via the GeneratedTask Object
    context "Boutiques Generated Class Properties" do
      it "should have the right task class name" do
        expect( @task_const.to_s ).to eq( "CbrainTask::BoutiquesTest" )
      end
      it "should have a tool" do
        expect( Tool.exists?(:cbrain_task_class => @task_const) ).to be true
      end
      it "should have no public path" do # Just test the help file
        expect( @task_const.public_path("edit_params_help.html") ).to eq( nil )
      end
      it "should have access to its generated source object" do
        expect( @task_const.generated_from ).to eq( @boutiquesTask  )
      end
      it "has all raw partials" do
        expect( @task_const.raw_partial(:task_params) ).not_to eq( nil )
        expect( @task_const.raw_partial(:show_params) ).not_to eq( nil )
        expect( @task_const.raw_partial(:edit_help)   ).not_to eq( nil )
      end
      it "has pretty param names" do
        allThere = TestArgs.all? { |s| @task_const.pretty_params_names[s] == s.to_s }
        expect( allThere ).to be true
      end
      it "has expected default values" do # Only -r has a default value
        expect( @task_const.default_launch_args[:'r'] ).to eq( 'r' )
      end
    end

    # Test an object instantiated from the portal class generated by the Boutiques framework
    context "Generated Portal Task" do
      # General properties of the Portal task class/object
      it "should have the right name" do
        expect( @task.name ).to eq( "BoutiquesTest" )
      end
      it "should have a bourreau" do
        expect( @task.bourreau ).not_to eq( nil )
      end
      it "should have a tool id" do
        expect( @task.tool.id  ).not_to eq( nil )
      end

      # The before_form method should fail if no UserFiles are given, but work otherwise
      # Here, UserFile existence is merely simulated, and before_form is tested in isolation
      describe "has a before_form method that" do
        before(:each) do
          @task.params = {}
        end
        it "should fail when no input files are given" do
          expect { @task.before_form }.to raise_error(CbrainError, "Error: this task requires at least one input file")
        end
      end

      # Test the after_form method of the object
      # We run essentially the same test inputs as those sent to the local script, except
      # that we skip tests that check aspects that the isolated after_form cannot handle
      describe "has an after_form method that" do
        # after_form cannot check userfiles or flag existence (i.e. against the application) in this isolated test
        ignoredMsgs = ["invalid or missing userfile"]
        BasicTests.all? do |t|
          # Ignore tests requiring file existence checks (10 is an exit code for file existence check failure)
          # or tests that would need to check against the actual application (e.g. recognize argument existence).
          # The latter problem is excluded at a different level than after_form (since no input form will be created for it).
          next true if !t[3].nil? || t[2]==10 || t[0].include?("unrecognized")
          # Perform after_form test
          it "after_form #{t[0]}" do
            @task.params_errors.clear # Reset to having no errors
            begin # Parse the input command line
              @task.params = ArgumentDictionary.( t[1].dup )
            rescue OptionParser::MissingArgument => e
              next # after_form does not need to check this, since rails puts a value in the hash
            end
            hasFileListFilled = ! @task.params[:f].nil? # Whether the file list parameter is in use
            @task.params[:f] ||= [] # after_form expects [], not nil, for empty file lists
            @replaceFileIds.( hasFileListFilled ) # replace the file paths with IDs
            @task.after_form # Run the method
            errMsgs = @task.params_errors.full_messages
            # Cannot check userfile existence and so on in this isolated test, so ignore those errors
            errMsgs.delete_if { |m| ignoredMsgs.any? { |e| m.include?(e) } }
            # When there is an error, the exit code should be non-zero; no errors should be present otherwise
            print( errMsgs )
            expect(
              (errMsgs.length == 0 && t[2] == 0) || (errMsgs.length > 0 && t[2] != 0)
            ).to be true
            @task.params = {} # Clean up; @task is shared between tests
          end # it block
        end # all? block
      end # describe block generated after_form method

      # Test the portal task with respect to its behaviour when a user wishes to launch multiple jobs for a single task
      context "works with cbcsv files" do

        # Setup the environment with several userfiles and cbcsv files
        before(:each) do
          # Helper for making cbcsv files. fs = array of userfiles that will make up the cbcsv rows.
          @generateCbcsv = lambda do |fs, name, mangler=nil|
            flist = CbrainFileList.new(
              :user             => @user,
              :user_id          => @UID,
              :group_id         => GID,
              :name             => name,
              :data_provider_id => DPID,
            )
            flist.save
            text = CbrainFileList.create_csv_file_from_userfiles( fs )
            text = mangler.( text ) unless mangler.nil?
            flist.cache_writehandle { |t| t.write( text ) }
            @task.params[:interface_userfile_ids] << flist.id
            flist # return the cbcsv object
          end
          # Fill in the minimal required arguments for the class (but save the mock UI chosen files)
          temp = @task.params[:interface_userfile_ids]
          @task.params = ArgumentDictionary.( MinArgs )
          @task.params[:interface_userfile_ids] = temp
          # Create some user files
          @userfiles   = (0..9).map { |i| @makeUserfile.( "f-#{i}" ) }
          # Create some cbcsvs
          @std1, @std2 = @generateCbcsv.(@userfiles[0..3],"std2.cbcsv"), @generateCbcsv.(@userfiles[4..7],"std1.cbcsv")
          # File input parameters
          @task.params[:C]   = @file_C.id # Replace as above, since it is a required argument
          @task.params[:f] ||= [] # after_form expects [], not nil, for empty file lists
          # after_form checking helper # TODO it should also allow inputting a string and ensuring at least one error message contains that string
          @afterFormShouldBe = lambda { |b| @task.after_form; expect( @task.params_errors.full_messages.length == 0 ).to be b }
        end

        # Clean up after each test by removing the cbcsvs we saved (includes destroying them on the data provider)
        after(:each) do
          Userfile.all.select { |f| f.is_a?(CbrainFileList) }.each { |uf| uf.destroy }
        end

        # Test the after_form error checking for multi-task launching
        describe "in after_form" do
          it "with one cbcsv file" do
            @task.params[:d] = @std1.id # single cbcsv
            @afterFormShouldBe.( true )
          end
          it "with more than one cbcsv files" do
            @task.params[:d], @task.params[:j] = @std1.id, @std2.id
            @afterFormShouldBe.( true )
          end
          it "with a cbcsv that does not have the cbcsv extension" do
            misnamed = @generateCbcsv.(@userfiles[0..3], "misname.m"  )
            @task.params[:d] = misnamed.id # single cbcsv without the extension
            @afterFormShouldBe.( true )
          end
          it "with a cbcsv with nil entries" do
            nilEntries = @generateCbcsv.(@userfiles[3..6], "hasNils.cbcsv",
              -> (text) { # manually add a nil entry to the cbcsv
                fs, rt, n = CbrainFileList::FIELD_SEPARATOR, CbrainFileList::RECORD_TERMINATOR, CbrainFileList::ATTRIBUTES_LIST.length
                splitTxt  = text.split( rt )
                nilRow    = '0' + fs*(n - 1)
                splitTxt  << nilRow
                splitTxt.join( fs )
              }
            )
            @task.params[:d] = nilEntries.id
            @afterFormShouldBe.( true )
          end
          it "to detect errors when lengths don't match" do
            smaller = @generateCbcsv.(@userfiles[8..9], "small.cbcsv")
            @task.params[:d], @task.params[:j] = @std1.id, smaller.id
            @afterFormShouldBe.( false )
          end
          it "to detect errors when a file does not exist" do
            noFile = @generateCbcsv.(@userfiles[2..5], "missing.cbcsv",
              -> (text) { # Lambda for mangling the input text so the first number becomes invalid (choose max + 1)
                v    = text.split(",")
                v[0] = Userfile.all.map { |f| f.id }.max + 1
                v.join(",")
              }
            )
            @task.params[:d] = noFile.id
            @afterFormShouldBe.( false )
          end
          it "to detect errors when a file is inaccessible" do
            # Create a new user and file for him/her
            user2 = FactoryGirl.create( :user )
            file2 = SingleFile.new({data_provider_id: DPID, name: "file2.tex", group_id: GID, user_id: user2.id})
            file2.save!
            @task.params[:interface_userfile_ids] << file2.id
            # Put the file in a cbcsv and check after_form
            cbcsvTest = @generateCbcsv.( [@userfiles[0], file2, @userfiles[1]], "cbcsvWithOthersFiles.cbcsv")
            @task.params[:d] = cbcsvTest.id
            # Make sure after_form catches the problem
            @afterFormShouldBe.( false )
          end
          it "to detect errors when a file is not a cbcsv but has the cbcsv extension" do
            @task.params[:d] = @makeUserfile.( 'fake.cbcsv' ).id
            @afterFormShouldBe.( false )
          end
        end

        # Test the final_task_list method i.e. the actual generation of multiple jobs from the task
        # Note the special case where there is a single file-type input is tested below # TODO
        describe "in final_task_list" do

        end

      end

    end # Generated portal task context block
  end # Local boutiques task (full mock app) description

  # Run tests on the generated portal tasks derived from a minimal task object
  # Note: can read warnings via e.g. @task.getlog
  describe 'Local boutiques task (minimal app):' do

    # Run before block to create Minimal task, added to by specific tests
    before(:each) do
      @descriptor = NewMinimalTask.()
      # Checks after_form output.
      # Uses two expects because we may wish to require a certain number of errors and at least one of their contents.
      @checkAfterForm = -> (task, checkVal=0, atLeastOneErrWith=nil) {
        task.after_form # Run the method
        errMsgs = task.params_errors.full_messages # Get any error messages
        expect( errMsgs.any? { |e| e.include? atLeastOneErrWith } ).to be true unless atLeastOneErrWith.nil?
        expect( errMsgs.length == checkVal ).to be true
      }
      # Generates a task object from the minimal mock app
      @generateTask = -> params {
        useDefaults = (params.is_a? String) && (params == 'defaults')
        genTask = SchemaTaskGenerator.generate(SchemaTaskGenerator.default_schema, @descriptor, false).integrate
        task = CbrainTask::MinimalTest.new
        task.params = useDefaults ? task.class.default_launch_args : params
        task
      }
    end

    # Test the object generated by the Boutiques generator
    context "Boutiques GeneratedTask Object" do
      it "should have the right names" do
        genTask = SchemaTaskGenerator.generate(SchemaTaskGenerator.default_schema, @descriptor, false).integrate
        expect( (CbrainTask::MinimalTest.new).name ).to eq( "MinimalTest" ) # Check for task instance
        expect( genTask.name ).to eq( "CbrainTask::MinimalTest" ) # Check for generated task class instance
      end
    end

    # Default-values work appropriately
    context 'Default values' do
      before(:each) do
        @descriptor['command-line'] += '[B] '
      end
      it "should work a regular type" do
        @descriptor['inputs'] << GenerateJsonInputDefault.('b','Number','A number arg',{'default-value' => 9})
        task = @generateTask.( 'defaults' )
        task.before_form
        @checkAfterForm.( task )
      end
      it "should work with appropriate enums" do
        @descriptor['inputs'] << GenerateJsonInputDefault.('b','Enum','An enum arg',{'enum-value-choices' => ['a','b','c'], 'default-value' => 'b'})
        task = @generateTask.( 'defaults' )
        task.before_form
        @checkAfterForm.( task )
      end
      it "should fail with an inappropriate enum value" do
        @descriptor['inputs'] << GenerateJsonInputDefault.('b','Enum','An enum arg',{'enum-value-choices' => ['a','b','c'], 'default-value' => 'd'})
        task = @generateTask.( 'defaults' )
        task.before_form
        @checkAfterForm.( task, 1, "acceptable value" ) # Should give an error relating to the enum having an unacceptable value
      end
    end

    # Ensure that disables/requires and groups are independent
    # In response to an after_form bug where generated group code relied on disables/requires code
    context "groups and disables/requires independence in after_form" do

      before(:each) do
        @descriptor['inputs'] << GenerateJsonInputDefault.('b','Number','A number arg')
        @descriptor['command-line'] += '[B] '
      end

      it "is satisfied when neither is present" do
        task = @generateTask.( { a: 'val' , b: '1'} )
        @checkAfterForm.( task )
      end
      it "is satisfied when only groups are present" do
        @descriptor['groups'] = [{'id' => 'G', 'name' => 'G', 'members' => ['a','b'], 'mutually-exclusive' => true}]
        task = @generateTask.( { a: 'val1' } )
        @checkAfterForm.( task )
      end
      it "is satisfied when only disables is present" do
        @descriptor['inputs'][0]['disables-inputs'] = ['b']
        task = @generateTask.( { a: 'val1' } )
        @checkAfterForm.( task )
      end
      it "is satisfied when only requires is present" do
        @descriptor['inputs'][0]['requires-inputs'] = ['b']
        task = @generateTask.( { a: 'val1', b: 9 } )
        @checkAfterForm.( task )
      end
    end # after_form independence

  end # Minimal app context

end # Portal side tests

