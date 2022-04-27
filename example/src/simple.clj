(ns simple
  (:require [clojure.data.csv :as csv])
  (:gen-class))

(defn -main [& args]
  (println (csv/read-csv "h1,h2\nfoo,bar\nbaz,qux"))
)
