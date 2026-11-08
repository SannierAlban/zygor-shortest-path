# Zygor + Shortest Path

Petit add-on « pont » pour **World of Warcraft: Forever** : il envoie la destination de l'étape en cours de
**Zygor Guides Viewer (Forever)** à **Shortest Path Forever**, qui trace alors le chemin le plus court
(marche, vols, bateaux, portails…) sur la carte et la minicarte.

Aucun des deux add-ons n'est modifié :

- Zygor est seulement observé (`hooksecurefunc` sur `ZGV.Pointer.FindTravelPath`, `ClearWaypoints`, etc.,
  plus une vérification chaque seconde) ; la destination lue est `ZGV.Pointer.DestinationWaypoint`.
- Shortest Path est piloté par son API publique `ShortestPathForever.API.NavigateRoute`, comme son
  intégration RestedXP. Le point est envoyé avec `hold = true` : c'est Zygor qui décide quand l'étape est finie.

Les étapes suivantes affichées dans la fenêtre Zygor (réglage « étapes à afficher », jusqu'à 5) sont envoyées
comme arrêts supplémentaires : Shortest Path guide vers l'étape en cours (minicarte et grande carte) et dessine
les trajets vers les étapes suivantes sur la grande carte, plus pâles. Les étapes sans coordonnées, celles que
Zygor masque (mauvaise faction, classe…) et celles au même endroit que la précédente ne créent pas d'arrêt ;
le pont regarde alors plus loin dans le guide (jusqu'à 15 étapes) pour compléter le nombre d'arrêts. Un PNJ qui
patrouille (étape avec `path` et sans `goto`) devient un arrêt au début de son trajet.

Par défaut la flèche et le tracé de Zygor sont masqués (via ses propres options `arrowshow` et
`maplines_enabled`) pour ne garder que ceux de Shortest Path. Les valeurs d'origine sont mémorisées et
restaurées avec `/zsp off`.

## Installation

Copier (ou lier) le dossier `ZygorShortestPath` dans `_forever_/Interface/AddOns/`, puis relancer le jeu.
Requiert `ZygorGuidesViewerForever` et `ShortestPathForever`.

## Commandes

| Commande | Effet |
|---|---|
| `/zsp` | État : liaison, destination Zygor, suivi par Shortest Path |
| `/zsp on` / `/zsp off` | Active / coupe la liaison (restaure la flèche et le tracé Zygor) |
| `/zsp etapes` | Affiche / masque les étapes suivantes sur la grande carte |
| `/zsp go` | Reprend la destination Zygor après un autre trajet Shortest Path |
| `/zsp fleche` | Affiche / masque la flèche Zygor |
| `/zsp trace` | Affiche / masque le tracé Zygor sur la carte |

## Limites

- En combat, Shortest Path refuse les nouveaux trajets : la destination est envoyée à la sortie du combat.
- Les retours au cadavre sont laissés à Shortest Path.
- Si Zygor renomme ses fonctions internes, le pont cesse simplement de suivre, sans erreur.
