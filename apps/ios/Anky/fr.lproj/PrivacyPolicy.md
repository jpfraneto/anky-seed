# Politique de confidentialité d’Anky

Entrée en vigueur et révision : 11 juillet 2026

Anky privilégie le stockage local. L’écriture de base fonctionne sans compte ni abonnement. Tes écrits restent sur l’appareil, sauf si tu choisis de les exporter ou sauvegarder, de contacter l’assistance, ou de demander explicitement une fonction générée sur le serveur.

## 1. Qui sommes-nous ?

Anky est exploité par **Anky, Inc.**, société du Delaware. Contact : **[support@anky.app](mailto:support@anky.app)**.

Cette politique couvre l’app iOS, anky.app, le serveur Anky, les achats, l’assistance et les services associés. Anky n’est pas un service médical, psychologique, d’urgence ni de conseil professionnel.

## 2. Fonctions gratuites et Pro

Restent gratuites, sans Anky Pro :

- Commencer et terminer de nouvelles sessions d’écriture
- Créer, continuer, enregistrer, parcourir, copier, exporter et supprimer des écrits locaux
- Lire les réflexions déjà enregistrées sur l’appareil
- Une impulsion d’écriture locale, sans serveur, quand Pro est inactif
- Le contrôle Temps d’écran, le choix des apps protégées et l’activation/désactivation de la protection
- Trois Pass rapides quotidiens selon la règle actuelle
- L’accès et le déverrouillage d’urgence
- Les peintures statiques jusqu’au niveau 8
- Les peintures personnalisées déjà livrées
- Les archives et l’historique
- Les réglages, sauvegardes locales/iCloud, import/export, suppression de compte, assistance et documents juridiques

Seuls exigent le droit actif `pro` en minuscules :

1. De nouvelles réflexions IA générées sur le serveur pour des écrits sans réflexion enregistrée, sous réserve des limites du service.
2. Des impulsions d’écriture IA du serveur à la place de l’alternative locale gratuite, sous réserve des limites.
3. L’accès complet au parcours de 96 jours.
4. Le déverrouillage automatique Temps d’écran pour le reste de la journée après l’objectif quotidien configuré.
5. Des suggestions adaptatives d’objectif quotidien.
6. La progression après le niveau 8, dont les peintures personnalisées et cérémonies ultérieures, selon la progression, l’écriture et les limites de sécurité, capacité et génération.

Les services générés sont toujours soumis à des limites raisonnables de service, sécurité, capacité et prévention des abus.

## 3. Données enregistrées localement

Anky conserve sur l’appareil ou dans son groupe partagé :

- Fichiers `.anky`, brouillons, reconstructions lisibles et index locaux
- Réflexions IA enregistrées et peintures téléchargées
- Temps d’écriture, niveau, parcours, objectif, Pass et état de déverrouillage
- Réglages, rappels, jetons d’apps/catégories Temps d’écran et état du contrôle
- Un identifiant pseudonyme d’auteur/utilisateur et des clés de signature protégées par le Trousseau iOS
- Une phrase de récupération, sauf sauvegarde volontaire dans le Trousseau iCloud
- Un cache d’abonnement non officiel pour la continuité visuelle ; les actions payantes exigent une vérification actuelle

Écrire, enregistrer, continuer, parcourir, copier, exporter, supprimer, lire une réflexion existante, utiliser le contrôle, les Pass ou l’urgence n’envoie pas tes écrits au serveur Anky.

Les choix Temps d’écran restent dans les frameworks Apple et le stockage local. Anky n’envoie pas la liste des apps protégées à son serveur.

## 4. Données envoyées pour les services générés

### Réflexions IA

Lorsque tu demandes une nouvelle réflexion, l’app envoie les octets exacts du fichier `.anky` au serveur Anky via une connexion authentifiée. Le serveur valide le fichier et son hachage, reconstruit le texte et l’envoie avec des instructions au fournisseur IA configuré. La réflexion revient sur l’appareil et y est enregistrée.

### Impulsions d’écriture IA

Lorsque Pro est vérifié et que tu demandes une impulsion serveur, l’écrit `.anky` actuel suit le même parcours. Si Pro est inactif ou invérifiable, l’app utilise l’alternative locale sans envoyer l’écrit pour cette impulsion.

### Peintures personnalisées après le niveau 8

Quand cette progression est disponible, l’app envoie l’écriture depuis le niveau précédent au serveur. Un modèle en extrait des thèmes visuels et le prompt dérivé est envoyé à un fournisseur d’images. Le texte brut est traité temporairement et n’est pas conservé dans la base. Les fichiers de peinture et métadonnées liés au compte sont stockés pour pouvoir être livrés à nouveau, jusqu’à la suppression du compte ou une obligation opérationnelle/légale.

Le service utilise **OpenRouter** pour router les modèles configurés. Le code actuel peut utiliser des modèles Anthropic, Google et DeepSeek pour le texte, et OpenAI pour les images. Les endpoints Bankr ou Poiesis ne sont utilisés que s’ils sont configurés ; une route sensible est ignorée sans confirmation du réglage requis de rétention zéro. Chaque fournisseur applique ses propres conditions.

Anky demande des options sans entraînement et à rétention zéro lorsqu’elles existent, sans pouvoir garantir des pratiques identiques chez tous les tiers. N’envoie pas de contenu que tu ne veux pas voir traité pour la fonction demandée.

## 5. Registres serveur et opérationnels

Le serveur utilise un identifiant pseudonyme issu du profil cryptographique local, et non un compte classique avec mot de passe. Les requêtes signées prouvent son contrôle sans transmettre la phrase de récupération.

Pour fournir et protéger le service, Anky peut conserver :

- L’identifiant pseudonyme
- Les hachages, durées et dates de sessions pour la progression, jamais le texte
- L’état des niveaux/cérémonies, les métadonnées et fichiers de peintures, la génération et l’idempotence
- Les quotas et compteurs anti-abus
- Le produit, la transaction, la boutique, la période, l’expiration et le droit `pro` reçus via RevenueCat
- Des événements internes (découverte, paywall, achat, expiration, urgence) associés à un identifiant haché ou pseudonyme
- Des diagnostics épurés : heure, version, plateforme, hachage de requête, route, fournisseur, catégorie d’état/erreur et latence

Le serveur est conçu pour ne pas conserver le texte brut ou reconstruit, ni les réflexions ou impulsions générées après la réponse. Anky n’entraîne pas ses propres modèles avec tes écrits. Du contenu ne peut être conservé que si tu le fournis volontairement à l’assistance, pour examiner un incident que tu signales ou pour respecter la loi.

Anky n’intègre ni publicité ni suivi entre apps. Il ne vend pas les données et n’utilise pas les écrits à des fins publicitaires. Les événements et diagnostics internes servent au fonctionnement, à la fiabilité, la capacité, la sécurité, la prévention des abus et à une analyse produit limitée.

## 6. Apple, RevenueCat et abonnements

Anky propose des abonnements mensuels et annuels facultatifs et auto-renouvelables via l’App Store. Les deux ouvrent exactement les mêmes fonctions Pro. Le prix localisé et les conditions affichés par Apple au moment de l’achat font foi.

La formule annuelle peut comporter un essai de trois jours uniquement pour une personne éligible et seulement si Apple l’affiche. La formule mensuelle n’a actuellement aucun essai de bienvenue. L’abonnement se renouvelle automatiquement sauf annulation dans les réglages d’abonnement Apple.

Apple gère paiement, renouvellement, annulation, facturation, historique et remboursements. Anky ne reçoit ni ne stocke les données complètes de carte bancaire.

RevenueCat valide les achats et fournit les droits. Apple et RevenueCat transmettent les données de produit, achat, transaction, abonnement, boutique, expiration, essai et droit, liées à l’identifiant pseudonyme. Acheter ou restaurer actualise l’état. Les accès promotionnels ou sans date de fin peuvent aussi activer Pro.

Anky ne vend ni n’utilise de crédits de réflexion, packs de crédits ou soldes de crédits.

## 7. Services facultatifs et choix

- **Sauvegarde iCloud chiffrée :** si activée, une archive AES-GCM des écrits et réflexions est placée dans iCloud Documents. La phrase de récupération peut être enregistrée séparément dans le Trousseau iCloud à ta demande.
- **Import/export/partage :** les fichiers vont vers la destination choisie. Anky ne contrôle pas les copies exportées.
- **Notifications :** iOS conserve l’autorisation et l’horaire. Le rappel de fin d’essai vient uniquement d’un essai actif vérifié.
- **Voix et photos :** si tu choisis ces check-ins, les permissions et règles Apple s’appliquent. L’image actuelle n’est pas envoyée au serveur ni utilisée pour une peinture personnalisée.
- **Image de profil facultative :** le selfie/avatar choisi pendant l’accueil est conservé dans les documents locaux de l’app et n’est pas envoyé au serveur. Il peut figurer dans les sauvegardes Apple que tu actives.
- **Assistance :** l’app ouvre ton client mail. Tu choisis d’envoyer adresse, ID d’assistance pseudonyme, version, texte, captures ou pièces jointes.

## 8. Conservation et suppression

Les données locales restent jusqu’à leur suppression, l’utilisation des outils intégrés, la suppression des sauvegardes ou de l’app. Supprimer l’app n’annule pas l’abonnement.

**Supprimer le compte et les données** envoie une demande authentifiée pour effacer les données serveur, puis retire écrits, réflexions, réglages, identifiants, récupération, caches et sauvegarde Anky iCloud accessible. Le serveur efface sessions, niveaux, événements, quotas, générations et peintures personnalisées sous le contrôle d’Anky.

Anky ne peut pas supprimer l’historique Apple, les dossiers RevenueCat nécessaires à la validation ou la loi, les messages d’assistance légitimement conservés, les exports ou sauvegardes contrôlées par Apple. Un webhook RevenueCat ultérieur peut recréer un état minimal d’abonnement.

Les données opérationnelles sont gardées seulement aussi longtemps que raisonnablement nécessaire pour ces finalités, la loi, la sécurité, la fraude/les abus, les litiges et la comptabilité. Contacte **[support@anky.app](mailto:support@anky.app)**.

## 9. Sécurité, transferts et droits

Nous utilisons des mesures raisonnables : transport chiffré, requêtes signées, Trousseau et sauvegardes chiffrées. Aucun système n’est parfait. Protège appareil, Apple ID, phrase de récupération et exports.

Anky, Inc. est aux États-Unis. Les données que tu envoies peuvent y être traitées ou dans les pays où opèrent les fournisseurs.

Selon ton lieu de résidence, tu peux disposer de droits d’accès, rectification, suppression, export, restriction ou opposition. Une grande partie des données reste locale et sous ton contrôle.

## 10. Enfants, modifications et contact

Anky ne s’adresse pas aux enfants de moins de 13 ans. Les moins de 18 ans doivent l’utiliser avec l’autorisation d’un responsable légal.

Nous pouvons mettre à jour cette politique et modifierons sa date de révision.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
