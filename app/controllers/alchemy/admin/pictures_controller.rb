module Alchemy
  module Admin
    class PicturesController < Alchemy::Admin::ResourcesController
      helper 'alchemy/admin/tags'

      before_action :load_resource,
        only: [:show, :edit, :update, :destroy, :info]

      authorize_resource class: Alchemy::Picture

      def index
        @size = params[:size].present? ? params[:size] : 'medium'
        @query = Picture.ransack(params[:q])
        @pictures = Picture.search_by(params, @query, pictures_per_page_for_size(@size))

        if in_overlay?
          archive_overlay
        end
      end

      def new
        @picture = Picture.new
        set_size_or_default
        if in_overlay?
          set_instance_variables
        end
      end

      def show
        @previous = @picture.previous(params)
        @next = @picture.next(params)
        @pages = @picture.essence_pictures.group_by(&:page)
        render action: 'show'
      end

      def create
        @picture = Picture.new(picture_params)
        @picture.name = @picture.humanized_name
        if @picture.save
          set_size_or_default
          if in_overlay?
            set_instance_variables
          end
          message = _t('Picture uploaded succesfully', name: @picture.name)
          render json: {files: [@picture.to_jq_upload], growl_message: message}, status: :created
        else
          message = _t('Picture validation error', name: @picture.name)
          render(
            json: {
              files: [@picture.to_jq_upload],
              growl_message: message
            },
            status: :unprocessable_entity
          )
        end
      end

      def edit_multiple
        @pictures = Picture.where(id: params[:picture_ids])
        @tags = @pictures.collect(&:tag_list).flatten.uniq.join(', ')
      end

      def update
        if @picture.update(picture_params)
          @message = {
            body: _t(:picture_updated_successfully, name: @picture.name),
            type: 'notice'
          }
        else
          @message = {
            body: _t(:picture_update_failed),
            type: 'error'
          }
        end
        render :update
      end

      def update_multiple
        @pictures = Picture.find(params[:picture_ids])
        @pictures.each do |picture|
          picture.update_name_and_tag_list!(params)
        end
        flash[:notice] = _t("Pictures updated successfully")
        redirect_to_index
      end

      def delete_multiple
        if request.delete? && params[:picture_ids].present?
          pictures = Picture.find(params[:picture_ids])
          names = []
          not_deletable = []
          pictures.each do |picture|
            if picture.deletable?
              names << picture.name
              picture.destroy
            else
              not_deletable << picture.name
            end
          end
          if not_deletable.any?
            flash[:warn] = _t(
              "These pictures could not be deleted, because they were in use",
              names: not_deletable.to_sentence
            )
          else
            flash[:notice] = _t("Pictures deleted successfully", :names => names.to_sentence)
          end
        else
          flash[:warn] = _t("Could not delete Pictures")
        end
      rescue Exception => e
        flash[:error] = e.message
      ensure
        redirect_to_index
      end

      def destroy
        name = @picture.name
        @picture.destroy
        flash[:notice] = _t("Picture deleted successfully", :name => name)
      rescue Exception => e
        flash[:error] = e.message
      ensure
        redirect_to_index
      end

      def flush
        FileUtils.rm_rf Rails.root.join('public', Alchemy::MountPoint.get, 'pictures')
        @notice = _t('Picture cache flushed')
      end

      private

      def pictures_per_page_for_size(size)
        case size
        when 'small'
          per_page = in_overlay? ? 25 : (per_page_value_for_screen_size * 2.9).floor
        when 'large'
          per_page = in_overlay? ? 4 : (per_page_value_for_screen_size / 1.7).floor + 1
        else
          per_page = in_overlay? ? 9 : (per_page_value_for_screen_size / 1.0).ceil + 4
        end
        return per_page
      end

      def in_overlay?
        params[:element_id].present?
      end

      def archive_overlay
        @content = Content.select('id').find_by(id: params[:content_id])
        @element = Element.select('id').find_by(id: params[:element_id])
        @options = options_from_params
        respond_to do |format|
          format.html { render partial: 'archive_overlay' }
          format.js   { render action:  'archive_overlay' }
        end
      end

      def redirect_to_index
        do_redirect_to admin_pictures_path(
          filter: params[:filter].presence,
          page: params[:page].presence,
          query: params[:query].presence,
          size: params[:size].presence,
          tagged_with: params[:tagged_with].presence
        )
      end

      def picture_params
        params.require(:picture).permit(:image_file, :upload_hash, :name, :tag_list)
      end

      def set_size_or_default
        @size = params[:size] || 'medium'
      end

      def set_instance_variables
        @while_assigning = true
        @content = Content.select('id').find_by(id: params[:content_id])
        @element = Element.select('id').find_by(id: params[:element_id])
        @options = options_from_params
        @page = params[:page] || 1
        @per_page = pictures_per_page_for_size(@size)
      end
    end
  end
end
