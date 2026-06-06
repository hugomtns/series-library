const { handleSeriesStateApiRequest } = require("./series-state-handler");

module.exports = function seriesState(req, res) {
  return handleSeriesStateApiRequest(req, res);
};
