const { handleSeriesStateApiRequest } = require("../series-state-handler");

module.exports = function seriesStateById(req, res) {
  return handleSeriesStateApiRequest(req, res, { imdbId: req.query.imdbId });
};
