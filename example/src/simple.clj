(ns simple
  (:require [clojure.data.csv :as csv])
  (:import (org.bouncycastle.asn1 ASN1Absent))
  (:gen-class))

(defn -main [& args]
  (println (csv/read-csv "h1,h2\nfoo,bar\nbaz,qux"))
  (println "Thankfully" (str ASN1Absent/INSTANCE)))
