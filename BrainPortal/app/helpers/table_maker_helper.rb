
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

# Helpers for making tables
module TableMakerHelper

  Revision_info=CbrainFileRevision[__FILE__]

  # Renders an +array+ into a 2D table. This method is
  # useful when the +array+ contains a set of elements all
  # of a similar type.
  #
  # If a block is given, the block will be invoked once
  # for each of the elements of the +array+, with three
  # arguments: |elem,row,col| where elem is the element of
  # the +array+, row is the row number of its table cell (starting
  # at zero) and col is its column number (also starting at
  # zero). Make sure the block declares all three arguments.
  # The returned value of the block will be the content of
  # the HTML TD elements of the table.
  #
  # Options control the layout of the table.
  #
  #   :rows => number of rows
  #   :cols => number of columns
  #
  # If no :rows and :cols are supplied, a ratio of
  # rows:cols can be provided:
  #
  #   :ratio => "numrows:numcols" # e.g. "4:2"
  #
  # Note that the method will try its best to fit the
  # number of elements of +array+ within the number of
  # rows and columns supplied. The default is to make
  # the table kind of square.
  #
  #   :table_class => class(es) for the HTML TABLE element
  #   :tr_class    => class(es) for the HTML TR elements
  #   :td_class    => class(es) for the HTML TD elements
  #   :tr_callback => a Proc which will receive |row| number,
  #                   and is expected to generate the full TR element
  #   :tr_callback => a Proc which will receive |elem,row,col|
  #                   and is expected to generate the full TD element
  #
  # For small arrays that don't need a full table generated,
  # the option :min_data and :min_data_join can be used to
  # make the method act like Array#join (but where each of the
  # element will still be passed to the block if it's given):
  #
  #   :min_data => number ; do not generate a table if +array+ has less
  #                than this number of elements. Instead just join them.
  #   :min_data_join => string ; when joining is triggered by :min_data,
  #                     this is the joining string. Default: ", ".
  #
  def array_to_table(array,options = {})
    numelems  = array.size
    return "" if numelems == 0

    result = ""

    if options[:min_data] && numelems < options[:min_data]
      joiner = options[:min_data_join] || ", "
      formatted = []
      if block_given?
        array.each_with_index { |elem,i| formatted << capture { h(yield(elem,0,i)) } }
      else
        formatted = array.map{ |elem| h(elem) }
      end
      result += formatted.join(joiner)
      return result.html_safe
    end

    rows,cols = complete_rows_cols(numelems,options[:rows],options[:cols],options[:ratio])

    tableclass   = options[:table_class]
    trclass      = options[:tr_class]
    tdclass      = options[:td_class]
    tableclass &&= " class=\"#{tableclass}\""
    trclass    &&= " class=\"#{trclass}\""
    tdclass    &&= " class=\"#{tdclass}\""

    tableid      = options[:table_id]
    tableid    &&= " id=\"#{tableid}\""

    tr_callback = options[:tr_callback]
    td_callback = options[:td_callback]
    tr_callback ||= Proc.new { |rownum|       "<tr#{trclass}>" }
    td_callback ||= Proc.new { |elem,row,col| "<td#{tdclass}>#{elem}</td>" }

    result += "<table#{tableclass}#{tableid}>\n"
    array.each_with_index do |elem,i|
      col = i % cols
      row = i / cols
      if col == 0
        result += "  " + tr_callback.call(row) + "\n"
      end
      formatted_elem = block_given? ? capture { h(yield(elem,row,col)) } : h(elem)
      result += "    " + td_callback.call(formatted_elem,row,col) + "\n"
      if col + 1 == cols
        result += "  </tr>\n"
      end
    end
    num_missing_tds = (cols - 1) - ((numelems-1) % cols)
    if num_missing_tds > 0
      result += "    <td colspan=\"#{num_missing_tds}\"></td>\n  </tr>\n"
    end
    result += "</table>\n"

    result.html_safe
  end

  private

  # If one or both of :rows or :cols is missing,
  # compute the missing values.
  def complete_rows_cols(size,rows,cols,ratio) #:nodoc:
    if cols.nil? && rows.nil?
      if ! ratio.blank? && ratio =~ /^(\d*[1-9]\d*):(\d*[1-9]\d*)$/
        rrat     = Regexp.last_match[1].to_i
        crat     = Regexp.last_match[2].to_i
        rattot   = rrat * crat                # total 'cells' in ratio grid
        cellent  = size.to_f / rattot.to_f    # entries per ratio grid cell
        cellrows = Math.sqrt(cellent)         # rows per ratio grid cell
        rows     = (cellrows * rrat).to_i
      else
        rows = Math.sqrt(size).to_i
      end
      rows = 1    if rows == 0
    end
    if rows.nil?
      cols = size if cols > size
      cols = 1    if cols == 0
      rows = (size.to_f / cols + 0.999).to_i
      rows = 1    if rows == 0
    end
    if cols.nil?
      rows = size if rows > size
      rows = 1    if rows == 0
      cols = size / rows
      cols = 1    if cols == 0
    end
    return rows,cols
  end
  
end
