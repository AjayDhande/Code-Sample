class Job::DatatablesManagement
  class Decorator
    include ActionView::Helpers::UrlHelper

    def initialize(job, user = nil, column_names = nil)
      @job = job
      @user = user
      @column_names = column_names
    end

    def to_hash
      @column_names.map do |field_name|
        if fields_whitelist.include?(field_name)
          if self.respond_to? field_name
            self.public_send(field_name)
          else
            @job.public_send(field_name)
          end
        else
          raise "field #{field_name} is not supported"
        end
      end
    end

    def edit_multiple
      "<input class='edit_multiple' type='checkbox' value='#{@job.id}'>"
    end

    def system_id
      "<a href='/jobs/#{@job.id}'>#{@job.system_id}</a>"
    end

    def owner_id
      if @job.owner.present?
        "<td>#{@job.owner.name}</td>"
      else
        "<td>No owner assigned</td>"
      end
    end
    
    def team_id
      if @job.team.present?
        "<td>#{@job.team.team_name}</td>"
      else
        "<td>No team assigned</td>"
      end
    end

    def updated_at
      @job.updated_at_formatted
    end

    def label
      if @job.label?
        "<div class='actor-indicator #{@job.should_act}'></div>#{@job.label}"
      else
        "<div class='actor-indicator'></div>Ticket creation"
      end
    end

    def label_without_indicator
      if @job.label?
        "<div class='#{@job.should_act}'></div>#{@job.label}"
      else
        "Ticket creation"
      end
    end

    def priority
      if @job.priority == 'Urgent'
        "<a href='/jobs/#{@job.id}/' class='glyphicon glyphicon-exclamation-sign notification'></a>"
      else
        ""
      end
    end

    def lightbox
      if @job.lightboxes.undeleted.any?
        "<a href='/jobs/#{@job.id}/lightboxes'>LightBox</a>"
      else
        ""
      end
    end

    def team_lightbox
      if @job.team_lightboxes.undeleted.any?
        current_slot = current_stage_slot(@job.stage)
        label = label_name(current_slot).upcase
        proof_document = @job.get_proof_document_by_slot(current_slot)
        ERB.new("<a data-toggle='tooltip' data-placement='right' data-html='true' data-original-title='<h5>Team Lightboxes for #{label} file</h5>
         <% @job.team.users.each do |user|
         @user = user %>
            <div class=row><div class=col-sm-6><%= @user.name %></div>
            <% @status = user_status(proof_document, @user) %>
            <div class=col-sm-6><div class=rectangle id=<%= @status %>><%= @status %></div></div></div><br>
           <% end %> '
           href='/jobs/#{@job.id}/lightboxes', class='link-underline'>(#{team_lightbox_sent_count(@job)}/#{team_lightbox_returned_count(@job)}/#{team_lightbox_accepted_count(@job)})</a>").result(binding)
      else
        ""
      end
    end

    def user_status(document, user)
      status = document.team_lightboxes.undeleted.where(receiver_id: user.id).last.status rescue nil
      status = status.present? ? status : "none sent"
    end

    def team_lightbox_sent_count(job)
      TeamLightbox.where(proof_document_id: job.proof_documents.pluck(:id)).undeleted.count
    end

    def team_lightbox_returned_count(job)
      TeamLightbox.where(proof_document_id: job.proof_documents.pluck(:id), status: "REJECTED").undeleted.count
    end

    def team_lightbox_accepted_count(job)
      TeamLightbox.where(proof_document_id: job.proof_documents.pluck(:id), status: "ACCEPTED").undeleted.count
    end

    def proof_order_plates_count_g
      count = @job.proof_order_plates_count_g
      count if count > 0
    end

    def proof_order_plates_count_h
      count = @job.proof_order_plates_count_h
      count if count > 0
    end

    def plates_arrival_date
      if @job.recent_plates_arrival_date
        if @user.client? || @user.client_manager? 
          append_plate_information(@job.recent_plates_arrival_date)
        else
          append_plate_information(link_to @job.recent_plates_arrival_date, edit_job_plates_delivery_path(@job), class: "delivery_link")
        end
      else
        if @user.client? || @user.client_manager? 
          append_plate_information("Create delivery")
        else
          append_plate_information(link_to "Create delivery", edit_job_plates_delivery_path(@job), class: "delivery_link")
        end
      end
    end

    def append_plate_information(value)
      value #+ '&nbsp&nbsp' + plates_delivery_additional_information
    end

    def sleeves_count
      if @job.sleeves_count.to_i > 0
        @job.sleeves_count
      else
        nil
      end
    end

    def plates_pieces
      if @job.plates_pieces.to_i > 0
        @job.plates_pieces
      else
        nil
      end
    end


    def plates_delivery_additional_information
      content = @job.plates_delivery_additional_information
      if content.present?
        escaped = CGI::escapeHTML(content)
        "<span class='glyphicon glyphicon-info-sign proof-notification' data-original-title='#{escaped}'></span>"
      else
        ""
      end
    end

    def label_name(slot)
      case slot.to_s
        when 'aw'   then 'artwork'
        when 'a100' then 'press-ready'
        when 'sr'   then 'plates'
        when 'ta'   then 'third-party approval'
        else slot
      end
    end

    def current_stage_slot(stage)
      case stage.to_s
        when 'artwork'  then 'aw'
        when 'prepress' then 'a100'
        when 'plates'   then 'sr'
        when 'delivery' then 'ta'
        when 'start'    then 'original'
        else stage
      end
    end

    private

    def edit_job_plates_delivery_path(job)
      "/jobs/#{job.id}/plates_delivery/edit"
    end

    def fields_whitelist
      @@fields_whitelist ||= [
        'edit_multiple',
        'system_id',
        'updated_at',
        'label',
        'priority',
        'owner_id',
        'team_id',
        'lightbox',
        'team_lightbox',
        'proof_order_plates_count_g',
        'proof_order_plates_count_h',
        'plates_arrival_date',
        'sleeves_count',
        'plates_pieces',
        'stage',
        'description',
        'client_short_name',
        'print_supplier_short_name',
        'first_reference',
        'end_customer_name',
        'cylinder_name',
        'plates_lengths',
        'plates_widths',
        'plates_pieces',
        'cached_plate_types',
        'cached_plate_names'
      ]
    end
  end

  def initialize(user)
    @user  = user
  end

  def client_filter_data(scope)
    scope.includes(:client)
         .uniq("client.id")
         .order("clients.short_name ASC")
         .pluck("clients.id", "clients.short_name")
  end

  def print_supplier_filter_data(scope)
    scope.includes(:print_supplier)
         .uniq("print_supplier.id")
         .where("print_suppliers.short_name IS NOT NULL")
         .order("print_suppliers.short_name ASC")
         .pluck("print_suppliers.id", "print_suppliers.short_name")
  end

  def index_all_client_short_names
    Client.order("clients.short_name ASC")
          .pluck("clients.id", "clients.short_name")
  end

  def index_all_printers_short_names
    PrintSupplier.where("print_suppliers.short_name IS NOT NULL")
                 .order("print_suppliers.short_name ASC")
                 .pluck("print_suppliers.id", "print_suppliers.short_name")
  end

  def index_all_end_customer_names
    @user.client
         .jobs
         .includes(:end_customer)
         .uniq("end_customers.id")
         .order("end_customers.name ASC")
         .pluck("end_customers.id", "end_customers.name")
  end

  def plates_all_client_short_names
    client_filter_data(plates_collection)
  end

  def plates_all_printers_short_names
    print_supplier_filter_data(plates_collection)
  end

  def plates_all_end_customer_names
    Job.where("team_id in (?)", @user.teams.map(&:id))
         .includes(:end_customer)
         .uniq("end_customers.id")
         .order("end_customers.name ASC")
         .pluck("end_customers.id", "end_customers.name")
  end

  def startup_all_client_short_names
    client_filter_data(startup_collection)
  end

  def startup_all_printers_short_names
    print_supplier_filter_data(startup_collection)
  end

  def running_all_client_short_names
    client_filter_data(running_collection)
  end

  def running_all_printers_short_names
    print_supplier_filter_data(running_collection)
  end

  def delivered_all_client_short_names
    client_filter_data(delivered_collection)
  end

  def delivered_all_printers_short_names
    print_supplier_filter_data(delivered_collection)
  end

  def startup_collection
    base_collection.visible.at_stage(['start', 'preflight', 'quotation'])
  end

  def running_collection
    base_collection.visible.at_stage(['design', 'artwork', 'prepress'])
  end

  def delivered_collection
    base_collection.visible.at_stage('delivery').with_labels('In Process')
  end

  def plates_collection
    if @user.client? 
      Job.where(team_id: @user.teams.map(&:id)).at_stage('plates')
    elsif @user.client_manager?
      @user.client.jobs.at_stage('plates')
    else
      Job.at_stage('plates')
    end
  end

  def startup_response(params)
    @params = params
    @jobs = startup_collection.includes(:client, :print_supplier, :end_customer)
    if @user.repro? || @user.production?
      process!
    else
      running_process!
    end
  end

  def running_response(params)
    @params = params
    @jobs = running_collection.includes(:client, :print_supplier, :end_customer)
    if @user.repro? || @user.production?
      process!
    else
      running_process!
    end
  end

  def delivered_response(params)
    @params = params
    @jobs = delivered_collection.includes(:client, :print_supplier, :end_customer)

    process!
  end

  def plates_response(params)
    @params = params
    @jobs = plates_collection.visible.includes(:client, :print_supplier, :cylinder, :quotation, :colors)

    process!
  end

  def index_response(params)
    @params = params
    @jobs = base_collection.includes(:client, :print_supplier, :end_customer)
    process!
  end
  
  def running_process!
    search!
    filter_jobs!
    order!
    serialize!
  end

  def process!
    search!
    filter!
    order!
    serialize!
  end

  private

  def searchable_columns_map
    @searchable_columns_map ||= {
      "client_short_name" => "client.short_name",
      "print_supplier_short_name" => "print_supplier.short_name",
      "end_customer_name" => "end_customer.name",
      "owner_id" => ["owner.first_name", "owner.last_name"],
      "team_id" => "team.team_name",
      "cylinder_name" => "cylinder.name",
      "plates_lengths" => "quotation.plates_lengths",
      "plates_widths" => "quotation.plates_widths",
      "plates_pieces" => "quotation.plates_pieces",
      "updated_at" => "updated_at_formatted",
      "plates_arrival_date" => "plates_arrival_delivery_method",
      "system_id" => ["id", "system_id"]
    }
  end

  def searchable_columns
    @params[:columns].map{|k, h| h}
                     .find_all{|h| h['s'] == 'true'}
                     .map{|h| searchable_columns_map[h['name']] || h['name'] }
                     .flatten
  end

  def search!
    # Remove trailing zeroes from each word
    @search_query = @params[:search][:value].split(" ").map{|s| s.sub(/^0+/, "") }.join(" ")

    if @search_query.present?
      @jobs = @jobs.dynamic_search(@search_query, searchable_columns)
    end
  end

  def filter!

    if @params.dig(:filter, :hidden).blank? and !@jobs.where_values_hash.has_key? "hidden"
      @jobs = @jobs.visible
    end
    if @params.dig(:filter, :stages).present?
      @jobs = @jobs.at_stage(@params.dig(:filter, :stages).map(&:downcase))
    else
      if @params.dig(:filter, :labels).present?
        @jobs = @jobs.with_labels(@params.dig(:filter, :labels))
      #else
        #@jobs = @jobs.with_labels([])
      end
    end

    [:client_id, :print_supplier_id, :end_customer_id].each do |filter_field|
      if @params.dig(:filter, filter_field).present?
        @jobs = @jobs.where(filter_field => @params.dig(:filter, filter_field))
      end
    end
    
    @total_records = @jobs.count

    @jobs = @jobs.limit(@params[:length])
    @jobs = @jobs.offset(@params[:start])
  end

  def filter_jobs!
    if @params.dig(:filter, :labels).present? && @params.dig(:filter, :labels).length > 1
      @jobs = @jobs.where(owner_id: @user.id).with_labels(@params.dig(:filter, :labels))
    elsif @params.dig(:filter, :labels).present? && @params.dig(:filter, :labels).include?("Visible")
      @jobs = @jobs
    else
      @jobs = @jobs.with_labels(["Clarify Needed", "Approval Needed", "Shared"])
    end

    @total_records = @jobs.count

    @jobs = @jobs.limit(@params[:length])
    @jobs = @jobs.offset(@params[:start])
  end

  def serialize!
    response = {}
    response[:draw] = @params[:draw].to_i
    response[:recordsTotal] = @total_records
    response[:recordsFiltered] = @total_records
    column_names = @params[:columns].map{|k, h| h[:name]}

    response[:data] = @jobs.map do |job|
      Job::DatatablesManagement::Decorator.new(job, @user, column_names).to_hash
    end

    response
  end

  def base_collection
    if @user.repro? || @user.production?
      Job.all
    elsif @user.client?
      Job.visible.where(team_id: @user.teams.map(&:id))
    elsif @user.client_manager?
      @user.client.jobs.visible
    end
  end
end
