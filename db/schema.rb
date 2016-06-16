# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160616142650) do

  create_table "amis", force: :cascade do |t|
    t.string "ami"
    t.string "operation"
  end

  create_table "instances", force: :cascade do |t|
    t.string   "accountid"
    t.string   "instanceid"
    t.string   "instancetype"
    t.string   "az"
    t.string   "tenancy"
    t.string   "platform"
    t.string   "network"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
  end

  create_table "modifications", force: :cascade do |t|
    t.string   "modificationid"
    t.string   "status"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
  end

  create_table "recommendation_caches", force: :cascade do |t|
    t.text     "object"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "recommendations", force: :cascade do |t|
    t.string   "rid"
    t.string   "az"
    t.string   "instancetype"
    t.string   "vpc"
    t.integer  "count"
    t.datetime "timestamp"
    t.string   "accountid"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
    t.string   "counts"
  end

  create_table "reserved_instances", force: :cascade do |t|
    t.string   "accountid"
    t.string   "reservationid"
    t.string   "instancetype"
    t.string   "az"
    t.string   "tenancy"
    t.string   "platform"
    t.string   "network"
    t.integer  "count"
    t.datetime "enddate"
    t.string   "status"
    t.string   "rolearn"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.string   "offering"
    t.integer  "duration"
  end

  create_table "setups", force: :cascade do |t|
    t.text     "regions"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
    t.integer  "minutes"
    t.datetime "nextrun"
    t.string   "password"
    t.boolean  "importdbr"
    t.string   "s3bucket"
    t.datetime "processed"
    t.boolean  "affinity"
    t.datetime "nextrefresh"
    t.integer  "minutesrefresh"
  end

  create_table "summaries", force: :cascade do |t|
    t.string   "instancetype"
    t.string   "az"
    t.string   "tenancy"
    t.string   "platform"
    t.integer  "total"
    t.integer  "reservations"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
  end

end
