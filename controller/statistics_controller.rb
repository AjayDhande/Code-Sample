#
class StatisticsController < ApplicationController
  include RedirectConcern
  include ApplicationHelper
  def tracking_link
    return if params[:token].nil?
    @tracking_link = TrackingLink.find_by_token params[:token]
    redirect(docs_url) and return unless @tracking_link.allowed?(current_user)
    @get_stats = true
    @pdf_file = Docs::File.find_by_doc_id(@tracking_link.doc.id)
    @elements_json = {}
    live_file = Docs::EditorLiveFile.active_file(@pdf_file.id).first
    return if live_file.nil?
    @elements_json = File.read(live_file.elements.file.file)
  end

  def doc
    return if params[:token].nil?
    @doc = Doc.find_by_group_id params[:token]
    redirect(docs_url) and return unless @doc.allowed?(current_user)
    @get_stats = true
    @pdf_file = Docs::File.find_by_doc_id(@doc.id)
    @elements_json = {}
    live_file = Docs::EditorLiveFile.active_file(@pdf_file.id).first
    return if live_file.nil?
    live_file_path = Rails.root.join('public', @pdf_file.file.store_dir, 'elements', 'live',@pdf_file.language,live_file.elements.file.filename)
    @elements_json = File.read(live_file_path)
  end

  def receiver; end

  def sessions
    if params[:type] == 'tl'
      tl = TrackingLink.find_by_token(params[:token])
      redirect(docs_url) and return unless tl.allowed?(current_user)
      unless tl.nil?
        @parent = tl_parent tl
        @sessions = tl.sessions#.viewed
      end
    elsif params[:type] == 'doc'
      doc = Doc.find_by_group_id(params[:token])
      redirect(docs_url) and return unless doc.allowed?(current_user)
      unless doc.nil?
        @parent = doc_parent doc
        @sessions = doc.sessions#.viewed
      end
    end
  end

  def receivers
    unless check_session_receiver(:receiver)
      if params[:type] == 'tl'
        tl = TrackingLink.find_by_token(params[:token])
        redirect(docs_url) and return unless tl.allowed?(current_user)
        unless tl.nil?
          @parent = tl_parent tl
          @receivers = tl.receivers#.views
        end
      elsif params[:type] ==  'doc'
        doc = Doc.find_by_group_id(params[:token])
        redirect(docs_url) and return unless doc.allowed?(current_user)
        unless doc.nil?
          @parent = doc_parent doc
          @receivers = doc.receivers#.views
        end
      end
      if params[:receiver].present?
        @receivers = @receivers.where(id: params[:receiver])
      else
        @receivers = @receivers.uniq
      end
    else
      if params[:type] == 'tl'
        tl = TrackingLink.find_by_token(params[:token])
        @parent = tl_parent tl
        @sessions = tl.sessions.where(id: params[:receiver].split(',')[0])
      elsif params[:type] ==  'doc'
        doc = Doc.find_by_group_id(params[:token])
        @parent = doc_parent doc
        @sessions = doc.sessions.where(id: params[:receiver].split(',')[0])
      end
    end
  end

  def kdf_stats_filter
    threshold = params[:threshold]
    doc_tl = Doc.find_by_group_id(params[:receiver]) if params[:parent_type] == 'doc'
    doc_tl = TrackingLink.find_by_token(params[:receiver]) if params[:parent_type] == 'tl'
    @parent = doc_parent doc_tl if params[:parent_type] == 'doc'
    @parent = tl_parent doc_tl if params[:parent_type] == 'tl'
    if params[:type] == 'chart_stats'
      get_charts(threshold, doc_tl)
    elsif params[:type] == 'stats_sessions'
      get_listing(threshold, doc_tl)
    elsif params[:type] == 'stats_receivers'
      get_receivers(threshold, doc_tl)
    elsif params[:type] == 'stats_receiver'
      get_receiver(threshold, doc_tl)
    end
  end

  private

  def tl_parent(tl)
    file =  tl.doc.docs_files.first
    {
        type: 'tracking_link',
        id: tl.id,
        id_field_name: 'tracking_link_id',
        num_pages: file.num_pages,
        page_tags: file.page_tags(true),
        view_threshold: tl.doc.page_viewed_sec
    }
  end

  def doc_parent(doc)
    file = doc.docs_files.first
    {
        type: 'doc',
        id: doc.id,
        id_field_name: 'doc_id',
        num_pages: file.num_pages,
        page_tags: file.page_tags(true),
        view_threshold: doc.page_viewed_sec
    }
  end

  def get_charts_filter(doc, threshold)

    types = { by_country: 'country',
      by_subdivision: 'subdivision',
      by_city: 'city',
      by_browser: 'browser',
      by_os: 'os_family',
      by_device: 'device' }

    types.each do |key, val|
      types[key] = threshold.blank? ? doc.session_info(val, t('stats.unknown'), 20, t('stats.other')) : doc.filter_session_info(val, t('stats.unknown'), 20, t('stats.other'), threshold)
    end
    types[:time_per_page] = view_time_per_page(doc, threshold)
    return types
  end

  def view_time_per_page(doc, threshold)
    types = []
    if threshold.blank?
      doc = doc.get_secs_viewed_by_page
    else
      doc = doc.filter_secs_viewed_by_page(threshold)
    end
    doc.each do |time_per_page|
      time_on_page = {}  
      time_on_page[:page]               = time_per_page[:page]
      time_on_page[:min_on_page]        = format_time(time_per_page[:secs])
      time_on_page[:secs_on_page]       = time_per_page[:secs]
      time_on_page[:total_min_on_page]  = format_time(time_per_page[:total_secs])
      time_on_page[:total_secs_on_page] = time_per_page[:total_secs]
      time_on_page[:views]              = time_per_page[:views]
      types << time_on_page
    end
    return types
  end

  def get_charts(threshold, doc)
    unless threshold.blank?
      viewers = doc.filter_viewers(threshold)
      get_total_secs_viewed = doc.filter_secs_viewed('total', threshold)
      percent_viewed = doc.filter_pages_viewed(threshold)
      most_viewed_pages = doc.filter_popular_pages(threshold)
      returning_viewers = doc.filter_returning_viewers(threshold)
      charts = get_charts_filter(doc, threshold)
    else
      viewers = doc.get_viewers()
      get_total_secs_viewed = doc.get_secs_viewed('total')
      percent_viewed = doc.get_pages_viewed
      most_viewed_pages = doc.get_popular_pages
      returning_viewers = doc.get_returning_viewers
      charts = get_charts_filter(doc, '')
    end
    total_time = format_time(get_total_secs_viewed)
    render json: { doc: doc, viewers: viewers, total_time: total_time, percent_viewed: percent_viewed, most_viewed_pages: most_viewed_pages, returning_viewers: returning_viewers, charts: charts }    
  end

  def get_listing(threshold, doc)
    sessions = doc.sessions.map{ |session|
      session.as_json.merge({
        date: format_date(session.created_at),
        receiver: get_session_receiver(session.receiver),
        engagement: number_to_percentage(session.get_engagement(@parent), precision: 0),
        percent_viewed: number_to_percentage(session.filter_pages_viewed(@parent, threshold), precision: 0),
        min_viewed: format_time(session.filter_secs_viewed('total', threshold)),
        sec_viewed: session.filter_secs_viewed('total', threshold),
        pages_by_time_spent: session.filter_pages_by_most_time_spent(threshold),
        page_tags: @parent[:page_tags],
        popular_exit_pages: session.get_exit_page(@parent)
      })
    }
    render json: { sessions: sessions }
  end

  def get_receivers(threshold, doc)
    receivers = doc.receivers.uniq.map{|receiver|
      receiver.as_json.merge({
        name: receiver.email,
        sessions: receiver.sessions,
        engagement: number_to_percentage(receiver.get_engagement(@parent), precision: 0),
        percent_viewed: number_to_percentage(receiver.get_pages_viewed(@parent), precision: 0),
        min_viewed: format_time(receiver.filter_secs_viewed(@parent, threshold)),
        sec_viewed: receiver.filter_secs_viewed(@parent, threshold),
        pages_by_time_spent: receiver.filter_pages_by_most_time_spent(@parent, threshold),
        page_tags: @parent[:page_tags],
        popular_exit_pages: receiver.get_exit_pages(@parent)
      })
    }
    render json: { receivers: receivers }
  end

  def get_receiver(threshold, doc)

    unless check_session_receiver(:viewer_id)
      receiver = doc.receivers.find_by(id: params[:viewer_id])
    else
      receiver = doc.sessions.find_by(id: params[:viewer_id].split(',')[0])
    end

    receiver = receiver.as_json.merge({
      id: receiver.id,
      name_reversed: receiver.try(:name_reversed),
      company_id: receiver.try(:company_id),
      name: receiver.try(:email),
      sessions: get_sessions(receiver, threshold),
      engagement: number_to_percentage(receiver.get_engagement(@parent), precision: 0),
      percent_viewed: number_to_percentage(receiver.get_pages_viewed(@parent), precision: 0),
      percent_viewed_tooltip: receiver.get_pages_viewed(@parent,'number'),
      min_viewed: format_time(receiver.filter_secs_viewed(@parent, threshold)),
      sec_viewed: receiver.filter_secs_viewed(@parent, threshold),
      pages_by_time_spent: filter_pages_by_most_time_spent(receiver, threshold),
      page_tags: @parent[:page_tags],
      popular_exit_pages: get_exit_pages(receiver),
      created_time_stamp: format_date(receiver.created_at),
      total_min_viewed: format_time(get_secs_viewed(receiver)),
      total_secs_viewed: get_secs_viewed(receiver),
      page_min_viewed: format_time(get_page_secs_viewed(receiver)),
      page_sec_viewed: get_page_secs_viewed(receiver),
      most_viewed_pages: filter_popular_pages(receiver, threshold),
      time_per_page: get_time_per_page(receiver, threshold, @parent),
      element_clicks: get_elements_click(receiver)
    })

    render json: { receiver: receiver }
  end

  def get_sessions(receiver, threshold)
    i = 0
    _receiver = ''
    unless receiver.try(:sessions).nil?
      _receiver = receiver.sessions
    else
      _receiver = [receiver]
    end

    return _receiver.map { |session|
      session.as_json.merge!({pages: session.session_pages.map { |page|
        page.as_json.merge!({
          min_viewed: format_time(page.seconds_on_page),
          seconds: page.seconds_on_page,
          date: format_date(page.created_at),
          landing_page: landing_page(page, i),
          page_tags: @parent[:page_tags],
          viewed_at: format_date(page.created_at),
          elements: elements(page)
        })
      }, 
        date: format_date(session.created_at),
        receiver: session.receiver,
        engagement: number_to_percentage(session.get_engagement(@parent), precision: 0),
        percent_viewed: number_to_percentage(session.filter_pages_viewed(@parent, threshold), precision: 0),
        min_viewed: format_time(session.filter_secs_viewed('total', threshold)),
        sec_viewed: session.filter_secs_viewed('total', threshold),
        pages_by_time_spent: session.filter_pages_by_most_time_spent(threshold),
        page_tags: @parent[:page_tags],
        popular_exit_pages: session.get_exit_page(@parent)
      })
    }
  end

  def landing_page(page, i)
    if(i == 0)
      page.tracking_link.landing_page
      i += 1
    end
  end

  def elements(page)
    return page.session_page_clicks.multi_click.map{|page_click|
      page_click.as_json.merge!({
        id: page_click.docs_element_id,
        name: I18n.translate("stats.js.messages.#{Docs::Element::TYPE_NAME[page_click.docs_element.element_type].downcase}"),
        clicks: page_click.clicks.to_s + ' ' + (page_click.clicks != 1 ? I18n.translate('stats.js.messages.clicks') : I18n.translate('stats.js.messages.click'))
      });
    }
  end

  def get_time_per_page(receiver, threshold, parent)
    time_per_pages = ''
    unless receiver.try(:sessions).nil?
      time_per_pages = receiver.filter_secs_viewed_by_page(parent, threshold)
    else
      time_per_pages = receiver.filter_secs_viewed_by_page(threshold)
    end

    types = []
    time_per_pages.each do |time_per_page|
      time_on_page = {}  
      time_on_page[:page]               = time_per_page[:page]
      time_on_page[:min_on_page]        = format_time(time_per_page[:secs])
      time_on_page[:secs_on_page]       = time_per_page[:secs]
      time_on_page[:total_min_on_page]  = format_time(time_per_page[:total_secs])
      time_on_page[:total_secs_on_page] = time_per_page[:total_secs]
      time_on_page[:views]              = time_per_page[:views]
      types << time_on_page
    end
    return types
  end

  def filter_pages_by_most_time_spent(receiver, threshold)
    unless receiver.try(:sessions).nil?
      receiver.filter_pages_by_most_time_spent(@parent, threshold)
    else
      receiver.filter_pages_by_most_time_spent(threshold)
    end
  end

  def get_exit_pages(receiver)
    unless receiver.try(:sessions).nil?
      receiver.get_exit_pages(@parent)
    else
      receiver.get_exit_page(@parent)
    end
  end

  def get_secs_viewed(receiver)
    unless receiver.try(:sessions).nil?
      receiver.get_secs_viewed(@parent, 'total')
    else
      receiver.get_secs_viewed(@parent)
    end
  end

  def get_page_secs_viewed(receiver)
    unless receiver.try(:sessions).nil?
      receiver.get_page_secs_viewed(@parent)
    else
      receiver.get_page_secs_viewed
    end
  end

  def get_elements_click(receiver)
    unless receiver.try(:sessions).nil?
      receiver.get_elements_click(@parent)
    else
      receiver.get_elements_click
    end
  end

  def filter_popular_pages(receiver, threshold)
    unless receiver.try(:sessions).nil?
      receiver.filter_popular_pages(threshold, @parent)
    else
      receiver.filter_popular_pages(threshold)
    end
  end

  def check_session_receiver(receiver)
    if params[receiver].nil?
      return false
    else
      return params[receiver].split(',')[1] == 'session'
    end
  end

  def get_session_receiver(receiver)
    unless receiver.nil?
      return {id: receiver.id, name: receiver.name.blank? ? receiver.email : receiver.name, email: receiver.email}
    end
  end

end
