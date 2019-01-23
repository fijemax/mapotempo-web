# Copyright © Mapotempo, 2014-2016
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
require 'coerce'

class V01::Tags < Grape::API
  helpers SharedParams
  helpers do
    # Never trust parameters from the scary internet, only allow the white list through.
    def tag_params
      p = ActionController::Parameters.new(params)
      p = p[:tag] if p.key?(:tag)
      p.permit(:label, :ref, :color, :icon, :icon_size)
    end
  end

  resource :tags do
    desc 'Fetch customer\'s tags.',
         nickname: 'getTags',
         is_array: true,
         success: V01::Entities::Tag
    params do
      optional :ids, type: Array[String], desc: 'Select returned tags by id separated with comma. You can specify ref (not containing comma) instead of id, in this case you have to add "ref:" before each ref, e.g. ref:ref1,ref:ref2,ref:ref3.', coerce_with: CoerceArrayString
    end
    get do
      tags = if params.key?(:ids)
               current_customer.tags.select { |tag| params[:ids].any? { |s| ParseIdsRefs.match(s, tag) } }
             else
               current_customer.tags.load
             end
      present tags, with: V01::Entities::Tag
    end

    desc 'Fetch tag.',
         nickname: 'getTag',
         success: V01::Entities::Tag
    params do
      requires :id, type: String, desc: SharedParams::ID_DESC
    end
    get ':id' do
      id = ParseIdsRefs.read(params[:id])
      present current_customer.tags.where(id).first!, with: V01::Entities::Tag
    end

    desc 'Create tag.',
         detail: 'By creating a tag, it will be possible to filter visits and create a planning with only necessary visits.',
         nickname: 'createTag',
         success: V01::Entities::Tag
    params do
      use :params_from_entity, entity: V01::Entities::Tag.documentation.except(:id).deep_merge(
          label: {required: true}
      )
    end
    post do
      tag = current_customer.tags.build(tag_params)
      tag.save!
      present tag, with: V01::Entities::Tag
    end

    desc 'Update tag.',
         nickname: 'updateTag',
         success: V01::Entities::Tag
    params do
      requires :id, type: String, desc: SharedParams::ID_DESC
      use :params_from_entity, entity: V01::Entities::Tag.documentation.except(:id)
    end
    put ':id' do
      id = ParseIdsRefs.read(params[:id])
      tag = current_customer.tags.where(id).first!
      tag.update! tag_params
      present tag, with: V01::Entities::Tag
    end

    desc 'Delete tag.',
         nickname: 'deleteTag'
    params do
      requires :id, type: String, desc: SharedParams::ID_DESC
    end
    delete ':id' do
      id = ParseIdsRefs.read(params[:id])
      current_customer.tags.where(id).first!.destroy
      status 204
    end

    desc 'Delete multiple tags.',
         nickname: 'deleteTags'
    params do
      requires :ids, type: Array[String], desc: 'Ids separated by comma. You can specify ref (not containing comma) instead of id, in this case you have to add "ref:" before each ref, e.g. ref:ref1,ref:ref2,ref:ref3.', coerce_with: CoerceArrayString
    end
    delete do
      Tag.transaction do
        current_customer.tags.select do |tag|
          params[:ids].any?{ |s| ParseIdsRefs.match(s, tag) }
        end.each(&:destroy)
        status 204
      end
    end
  end
end
