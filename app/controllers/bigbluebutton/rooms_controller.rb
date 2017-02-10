# -*- coding: utf-8 -*-
require 'bigbluebutton_api'

class Bigbluebutton::RoomsController < ApplicationController
  include BigbluebuttonRails::InternalControllerMethods

  before_filter :find_room, :except => [:index, :create, :new]

  # set headers only in actions that might trigger api calls
  before_filter :set_request_headers, :only => [:join_mobile, :end, :running, :join, :destroy]

  before_filter :join_check_room, :only => :join
  before_filter :join_user_params, :only => :join
  before_filter :join_check_can_create, :only => :join
  before_filter :join_check_redirect_to_mobile, :only => :join

  respond_to :html, :except => :running
  respond_to :json, :only => [:running, :show, :new, :index, :create, :update]

  def index
    @rooms ||= BigbluebuttonRoom.all
    @organization = Organization.find_by(primary: params[:org_pk])
    respond_with(@rooms)
  end

  def show
    respond_with(@room)
  end

  def new
    @room ||= BigbluebuttonRoom.new
    respond_with(@room)
  end

  def edit
    respond_with(@room)
  end

  def create
    @room ||= BigbluebuttonRoom.new(room_params)

    if params[:bigbluebutton_room] and
        (not params[:bigbluebutton_room].has_key?(:meetingid) or
         params[:bigbluebutton_room][:meetingid].blank?)
      @room.meetingid = @room.name
    end

    respond_with @room do |format|
      if @room.save
        message = t('bigbluebutton_rails.rooms.notice.create.success')
        format.html {
          redirect_to_using_params bigbluebutton_room_path(@room), :notice => message
        }
        format.json {
          render :json => { :message => message }, :status => :created
        }
      else
        format.html {
          message = t('bigbluebutton_rails.rooms.notice.create.failure')
          redirect_to_params_or_render :new, :error => message
        }
        format.json { render :json => @room.errors.full_messages, :status => :unprocessable_entity }
      end
    end
  end

  def update
    respond_with @room do |format|
      if @room.update_attributes(room_params)
        message = t('bigbluebutton_rails.rooms.notice.update.success')
        format.html {
          redirect_to_using_params bigbluebutton_room_path(@room), :notice => message
        }
        format.json { render :json => { :message => message } }
      else
        format.html {
          message = t('bigbluebutton_rails.rooms.notice.update.failure')
          redirect_to_params_or_render :edit, :error => message
        }
        format.json { render :json => @room.errors.full_messages, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    error = false
    begin
      @room.fetch_is_running?
      @room.send_end if @room.is_running?
      message = t('bigbluebutton_rails.rooms.notice.destroy.success')
    rescue BigBlueButton::BigBlueButtonException => e
      error = true
      message = t('bigbluebutton_rails.rooms.notice.destroy.success_with_bbb_error', :error => e.to_s[0..200])
    end

    # TODO: what if it fails?
    @room.destroy

    respond_with do |format|
      format.html {
        flash[:error] = message if error
        redirect_to_using_params bigbluebutton_rooms_url
      }
      format.json {
        if error
          render :json => { :message => message }, :status => :error
        else
          render :json => { :message => message }
        end
      }
    end
  end

  # Used to join users into a meeting. Most of the work is done in before filters.
  # Can be called via GET or POST and accepts parameters both in the POST data and URL.
  def join
    @organization = Organization.find_by(primary: params[:org_pk])
    join_internal(@user_name, @user_role, @user_id)
  end

  # Used to join private rooms or to invite anonymous users (not logged)
  def invite
    @organization = Organization.find_by(primary: params[:org_pk])
    respond_with @room do |format|

      @user_role = bigbluebutton_role(@room)
      if @user_role.nil?
        raise BigbluebuttonRails::RoomAccessDenied.new
      else
        format.html
      end

    end
  end

  def running
    begin
      @room.fetch_is_running?
    rescue BigBlueButton::BigBlueButtonException => e
      flash[:error] = e.to_s[0..200]
      render :json => { :running => "false", :error => "#{e.to_s[0..200]}" }
    else
      render :json => { :running => "#{@room.is_running?}" }
    end
  end

  def end
    error = false
    begin
      @room.fetch_is_running?
      if @room.is_running?
        @room.send_end
        message = t('bigbluebutton_rails.rooms.notice.end.success')
      else
        error = true
        message = t('bigbluebutton_rails.rooms.notice.end.not_running')
      end
    rescue BigBlueButton::BigBlueButtonException => e
      error = true
      message = e.to_s[0..200]
    end

    if error
      respond_with do |format|
        format.html {
          flash[:error] = message
          redirect_to_using_params :back
        }
        format.json { render :json => message, :status => :error }
      end
    else
      respond_with do |format|
        format.html {
          redirect_to_using_params bigbluebutton_room_path(@room), :notice => message
        }
        format.json { render :json => message }
      end
    end
  end

  def join_mobile
    Rails.logger.debug("------------- Join Mobile -------------")
    Rails.logger.debug(params[:org_pk])
    @organization = Organization.find_by(primary: params[:org_pk])
    filtered_params = select_params_for_join_mobile(params.clone)
    @join_mobile = join_bigbluebutton_room_url(@room, filtered_params.merge({:auto_join => '1' }))
    @join_desktop = join_bigbluebutton_room_url(@room, filtered_params.merge({:desktop => '1' }))
  end

  def fetch_recordings
    error = false

    if @room.server.nil?
      error = true
      message = t('bigbluebutton_rails.rooms.errors.fetch_recordings.no_server')
    else
      begin
        # filter only recordings created by this room
        filter = { :meetingID => @room.meetingid }
        @room.server.fetch_recordings(filter)
        message = t('bigbluebutton_rails.rooms.notice.fetch_recordings.success')
      rescue BigBlueButton::BigBlueButtonException => e
        error = true
        message = e.to_s[0..200]
      end
    end

    respond_with do |format|
      format.html {
        flash[error ? :error : :notice] = message
        redirect_to_using_params bigbluebutton_room_path(@room)
      }
      format.json {
        if error
          render :json => { :message => message }, :status => :error
        else
          render :json => true, :status => :ok
        end
      }
    end
  end

  def recordings
    @recordings ||= @room.recordings
    respond_with(@recordings)
  end

  def generate_dial_number
    pattern = params[:pattern].blank? ? nil : params[:pattern]
    if @room.generate_dial_number!(pattern)
      message = t('bigbluebutton_rails.rooms.notice.generate_dial_number.success')
      respond_with do |format|
        format.html { redirect_to_using_params :back, notice: message }
        format.json { render json: true, status: :ok }
      end
    else
      message = t('bigbluebutton_rails.rooms.errors.generate_dial_number.not_unique')
      respond_with do |format|
        format.html {
          flash[:error] = message
          redirect_to_using_params :back
        }
        format.json { render json: { message: message }, status: :error }
      end
    end
  end

  protected

  def find_room
    @room ||= BigbluebuttonRoom.find_by_param(params[:id])
  end

  def set_request_headers
    unless @room.nil?
      @room.request_headers["x-forwarded-for"] = request.remote_ip
    end
  end

  def join_check_room
    @room ||= BigbluebuttonRoom.find_by_param(params[:id]) unless params[:id].blank?
    if @room.nil?
      message = t('bigbluebutton_rails.rooms.errors.join.wrong_params')
      redirect_to :back, :notice => message
    end
  end

  # Checks the parameters received when calling `join` and sets them in variables to
  # be accessed by other methods. Sets the user's name, id and role. Gives priority to
  # a logged user over the information provided in the params.
  def join_user_params
    # gets the user information, given priority to a possible logged user
    if bigbluebutton_user.nil?
      @user_name = params[:user].blank? ? nil : params[:user][:name]
      @user_id = nil
    else
      @user_name = bigbluebutton_user.first_name + " " + bigbluebutton_user.last_name
      @user_id = bigbluebutton_user.id
    end

    # the role: nil means access denied, :key means check the room
    # key, otherwise just use it
    if params[:key] == @room.attendee_key
      @user_role = :attendee
    elsif params[:key] == @room.moderator_key
      @user_role = :moderator
    else
      @user_role = nil
    end

    if @user_role.nil?
      raise BigbluebuttonRails::RoomAccessDenied.new
    end

    Rails.logger.debug("User Role")
    Rails.logger.debug(@user_role.inspect)
    Rails.logger.debug("User name")
    Rails.logger.debug(@user_name)
    Rails.logger.debug(@user_role.nil?)
    Rails.logger.debug(@user_name.blank?)

    if @user_role.nil? or @user_name.blank?
      Rails.logger.debug("Inside OR")
      flash[:error] = t('bigbluebutton_rails.rooms.errors.join.failure')
      redirect_to_on_join_error
    end
  end

  # Aborts and redirects to an error if the user can't create a meeting in
  # the room and it needs to be created.
  def join_check_can_create
    Rails.logger.debug("join check can create............")
    Rails.logger.debug(@user_role)
    if @room.fetch_is_running?
      Rails.logger.debug("It's running.")
    else
      Rails.logger.debug("It's not running.")
    end
    unless @room.fetch_is_running?
      Rails.logger.debug("Is it running?")
      unless bigbluebutton_can_create?(@room, @user_role)
        Rails.logger.debug("can create?")
        flash[:error] = t('bigbluebutton_rails.rooms.errors.join.cannot_create')
        redirect_to_on_join_error
      end
    end
  rescue BigBlueButton::BigBlueButtonException => e
    Rails.logger.debug("Rescued................")
    flash[:error] = e.to_s[0..200]
    redirect_to_on_join_error
  end

  # If the user called the join from a mobile device, he will be redirected to
  # an intermediary page with information about the mobile client. A few flags set
  # in the params can override this behavior and skip this intermediary page.
  def join_check_redirect_to_mobile
    Rails.logger.debug("-------- check redirect to mobile ----------")
    Rails.logger.debug(params[:org_pk])
    return if !BigbluebuttonRails.use_mobile_client?(browser) ||
              BigbluebuttonRails.value_to_boolean(params[:auto_join]) ||
              BigbluebuttonRails.value_to_boolean(params[:desktop])

    # since we're redirecting to an intermediary page, we set in the params the params
    # we received, including the referer, so we can go back to the previous page if needed
    filtered_params = select_params_for_join_mobile(params.clone)
    begin
      filtered_params[:redir_url] = Addressable::URI.parse(request.env["HTTP_REFERER"]).path
    rescue
    end

    redirect_to join_mobile_bigbluebutton_room_path(@room, org_pk: params[:org_pk], filtered_params)
  end

  # Selects the params from `params` that should be passed in a redirect to `join_mobile` and
  # adds new parameters that might be needed.
  def select_params_for_join_mobile(params)
    params.blank? ? {} : params.slice("user", "redir_url")
  end

  # Default method to redirect after an error in the action `join`.
  def redirect_to_on_join_error
    redirect_to_using_params_or_back(invite_bigbluebutton_room_path(@room, org_pk: params[:org_pk]))
  end

  # The internal process to join a meeting.
  def join_internal(username, role, id)
    Rails.logger.debug("Join Internal................")
    begin
      # first check if we have to create the room and if the user can do it
      unless @room.fetch_is_running?
        Rails.logger.debug("Room is not running...............")
        if bigbluebutton_can_create?(@room, role)
          Rails.logger.debug("User can create meeting.")
          user_opts = bigbluebutton_create_options(@room)
          Rails.logger.debug(user_opts)
          if @room.create_meeting(bigbluebutton_user, request, user_opts)
            Rails.logger.debug("Meeting created...............")
            logger.info "Meeting created: id: #{@room.meetingid}, name: #{@room.name}, created_by: #{username}, time: #{Time.now.iso8601}"
          end
        else
          flash[:error] = t('bigbluebutton_rails.rooms.errors.join.cannot_create')
          redirect_to_on_join_error
          return
        end
      end

      # gets the token with the configurations for this user/room
      token = @room.fetch_new_token
      options = if token.nil? then {} else { :configToken => token } end

      # set the create time and the user id, if they exist
      options.merge!({ createTime: @room.create_time }) unless @room.create_time.blank?
      options.merge!({ userID: id }) unless id.blank?

      # room created and running, try to join it
      url = @room.join_url(username, role, nil, options)
      unless url.nil?

        # change the protocol to join with a mobile device
        if BigbluebuttonRails.use_mobile_client?(browser) &&
           !BigbluebuttonRails.value_to_boolean(params[:desktop])
          url.gsub!(/^[^:]*:\/\//i, "bigbluebutton://")
        end

        redirect_to url
      else
        flash[:error] = t('bigbluebutton_rails.rooms.errors.join.not_running')
        redirect_to_on_join_error
      end

    rescue BigBlueButton::BigBlueButtonException => e
      flash[:error] = e.to_s[0..200]
      redirect_to_on_join_error
    end
  end

  def room_params
    unless params[:bigbluebutton_room].nil?
      params[:bigbluebutton_room].permit(*room_allowed_params)
    else
      {}
    end
  end

  def room_allowed_params
    [ :notify, :name, :key, :org_pk, :server_id, :meetingid, :attendee_key, :moderator_key, :welcome_msg,
      :private, :logout_url, :dial_number, :voice_bridge, :max_participants, :owner_id,
      :owner_type, :external, :param, :record_meeting, :duration, :default_layout, :presenter_share_only,
      :auto_start_video, :auto_start_audio, :background,
      :moderator_only_message, :auto_start_recording, :allow_start_stop_recording,
      :metadata_attributes => [ :id, :name, :content, :_destroy, :owner_id ] ]
  end
end
