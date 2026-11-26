"""S5 - M4 : pipeline PySpark sur l'extrait des taxis.

Lancement : python volumetrie/spark/pipeline.py ENTREE.jsonl DOSSIER_SORTIE
"""
import argparse
from pathlib import Path

from pyspark.sql import SparkSession, functions as F

ZONES = Path(__file__).resolve().parents[1] / "secours" / "zones.csv"

parser = argparse.ArgumentParser()
parser.add_argument("entree", type=Path)
parser.add_argument("sortie", type=Path)
args = parser.parse_args()

spark = (SparkSession.builder.master("local[2]").appName("taxis-s5")
         .config("spark.sql.shuffle.partitions", "2").getOrCreate())
spark.sparkContext.setLogLevel("ERROR")

try:
    # 1. lecture et schéma
    brut = spark.read.json(str(args.entree))
    print("--- Schéma du JSONL")
    brut.printSchema()
    nb_lues = brut.count()

    # 2. typage et projection
    trajets = brut.select(
        F.col("Start_Zone").cast("int").alias("zone_id"),
        F.col("Trip_Distance").cast("double").alias("distance_miles"),
        F.col("Trip_Duration").cast("double").alias("duree_s"),
    )

    # 3. filtre (mêmes règles que l'extraction)
    trajets = trajets.where(
        F.col("zone_id").isNotNull()
        & (F.col("distance_miles") > 0) & (F.col("distance_miles") <= 100)
        & (F.col("duree_s") > 0) & (F.col("duree_s") <= 14400)
    )

    # 4. colonnes calculées : distance en km et vitesse en km/h
    trajets = (trajets
               .withColumn("distance_km", F.col("distance_miles") * 1.609344)
               .withColumn("vitesse_kmh", F.col("distance_km") / (F.col("duree_s") / 3600)))
    nb_filtrees = trajets.count()
    print(f"Lignes lues : {nb_lues} | après filtre : {nb_filtrees} | enlevées : {nb_lues - nb_filtrees}")

    # 5. table des zones et contrôle de la clé
    zones = (spark.read.option("header", True).csv(str(ZONES))
             .select(F.col("LocationID").cast("int").alias("zone_id"),
                     F.col("Borough").alias("arrondissement"),
                     F.col("Zone").alias("zone")))
    print("--- Schéma des zones")
    zones.printSchema()
    nb_zones = zones.count()
    nb_cles = zones.select("zone_id").distinct().count()
    nb_cles_vides = zones.where(F.col("zone_id").isNull()).count()
    print(f"Zones : {nb_zones} lignes, {nb_cles} clés différentes, {nb_cles_vides} clé vide")
    assert nb_zones == nb_cles and nb_cles_vides == 0, "la clé zone_id n'est pas unique"

    # 6. trajets sans zone connue
    sans_zone = trajets.join(zones, "zone_id", "left_anti")
    print(f"Trajets sans zone connue : {sans_zone.count()}")
    sans_zone.groupBy("zone_id").count().orderBy("zone_id").show()

    # 7. jointure (left pour ne perdre aucun trajet)
    joint = trajets.join(zones, "zone_id", "left")
    nb_joint = joint.count()
    print(f"Avant jointure : {nb_filtrees} | après jointure : {nb_joint}")
    assert nb_joint == nb_filtrees, "la jointure a ajouté des lignes"

    # 8. agrégation par arrondissement
    resultat = (joint
                .withColumn("arrondissement", F.coalesce("arrondissement", F.lit("Zone inconnue")))
                .groupBy("arrondissement")
                .agg(F.count("*").alias("nb_trajets"),
                     F.round(F.avg("distance_km"), 2).alias("distance_moy_km"),
                     F.round(F.avg("duree_s") / 60, 1).alias("duree_moy_min"),
                     F.round(F.avg("vitesse_kmh"), 1).alias("vitesse_moy_kmh"))
                .orderBy(F.desc("nb_trajets")))

    # 9. partitions et plan d'exécution
    print("Partitions des trajets :", trajets.rdd.getNumPartitions())
    print("Partitions du résultat :", resultat.rdd.getNumPartitions())
    print("--- Plan d'exécution")
    resultat.explain()

    # 10. export Parquet (erreur si le dossier existe déjà) puis relecture
    resultat.write.mode("errorifexists").parquet(str(args.sortie))
    relu = spark.read.parquet(str(args.sortie))
    print("--- Parquet relu")
    relu.orderBy(F.desc("nb_trajets")).show(truncate=False)
    total = relu.agg(F.sum("nb_trajets")).first()[0]
    print(f"Total des trajets dans le Parquet : {total} (attendu {nb_filtrees})")
    assert total == nb_filtrees
finally:
    spark.stop()
