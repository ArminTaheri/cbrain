
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

class Demand < ActiveRecord::Base

  validate              :strip_blanks

  attr_accessible       :title, :first, :middle, :last,
                        :institution, :department, :position, :email,
                        :street1, :street2, :city, :province, :country, :postal_code,
                        :login, :time_zone, :comment

  validates_presence_of :first, :last,
                        :institution, :department, :position, :email,
                        :city, :province, :country, :confirm_token

  validates             :login,
                        :demand_username_format => true,
                        :allow_blank => true

  validates             :email, :format => { :with => /^(\w[\w\-\.]*)@(\w[\w\-]*\.)+[a-z]{2,}$|^\w+@localhost$/i }

  def strip_blanks #:nodoc:
    [
      :title, :first, :middle, :last,
      :institution, :department, :position, :email,
      :street1, :street2, :city, :province, :country, :postal_code,
      :login, :comment
    ].each do |att|
      val = read_attribute(att) || ""
      write_attribute(att, val.strip)
    end
    self.login = (self.login.presence || "").downcase
    true
  end

  # Token inserted in email to new user to confirm their email
  def generate_token
    tok = ""
    tok += ("a".."z").to_a[rand(26)]
    19.times {
      c=sprintf("%d",rand(10)); tok += c
    }
    self.confirm_token = tok
  end

  def full #:nodoc:
    "#{title} #{first} #{middle} #{last}".strip.gsub(/  +/, " ")
  end

  def approved? #:nodoc:
    self.approved_by.present? && self.approved_at.present?
  end

  def is_suspicious? #:nodoc:
    country = (self.country.presence || "").downcase
    full_cat = "#{full_name}|#{institution}|#{department}|#{email}|#{country}|#{province}|#{city}|#{postal_code}|#{street1}|#{street2}|#{comment}|#{login}".downcase
    return true if full_cat =~ /qwe|tyu|uio|asd|sdf|dfg|fgh|hjk|jkl|zxc|xcv|cvb|vbn|bnm/i # keyboard banging
    return true if full_cat =~ /shit|fuck|cunt|blah|piss|vagina|mother|nigg|negro/i # obscenities
    return true if full_cat =~ /([a-z])\1\1\1/i
    return true if first.downcase == last.downcase || first.downcase == middle.downcase || middle.downcase == last.downcase
    return true if first.downcase !~ /[a-z]/i || last.downcase !~ /[a-z]/i
    false
  end

  alias full_name full

  def dup_email? #:nodoc:
    User.exists?(:email => self.email)
  end

  def dup_login? #:nodoc:
    User.exists?(:login => self.login)
  end

  # This is the method that actually creates the user in CBRAIN's database
  def after_approval

    res = ApprovalResult.new
    unless self.valid?
      res.success     = false
      res.diagnostics = "Account request invalid:\n"
      self.errors.full_messages.each{ |msg|
        res.diagnostics << "\n" + msg
      }
      return res
    end

    if self.dup_login?
      res.diagnostics = "Failed to create user " + self.login + ", already exists"
      res.success     = false
      return res
    end

    pass = User.random_string

    u = User.new
    #u.title                   = self.title
    u.full_name               = self.full
    u.login                   = self.login
    u.email                   = self.email
    #u.institution             = self.institution
    #u.department              = self.department
    #u.position                = self.position
    #u.street1                 = self.street1
    #u.street2                 = self.street2
    u.city                    = self.city
    #u.province                = self.province
    u.country                 = self.country
    #u.postal_code             = self.postal_code
    u.time_zone               = self.time_zone
    #u.comment                 = self.comment
    u.type                    = 'NormalUser'
    u.password                = pass
    u.password_confirmation   = pass
    u.password_reset          = true

    if u.save()
      res.plain_password = pass
      res.diagnostics    = "Created as UID #{u.id}"
      res.success        = true
    else
      res.diagnostics    = "Could not save user"
      res.success        = false
    end

    res
  end

  class ApprovalResult
    attr_accessor :diagnostics, :plain_password, :success

    def to_s #:nodoc:
      self.diagnostics.presence.to_s
    end

  end

end

