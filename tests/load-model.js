// Loads ../Model.js (a QML .pragma library) into Node for testing.
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const src = fs
  .readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const ctx = { Date, Math, JSON, Number, Object, String, Array, isFinite, isNaN, console }
vm.createContext(ctx)
vm.runInContext(src, ctx)
module.exports = ctx
