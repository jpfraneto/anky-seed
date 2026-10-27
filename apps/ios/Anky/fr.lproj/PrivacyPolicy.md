# Politique de confidentialité d’Anky

En vigueur et révisée le : 27 octobre 2026

Anky (Anky : Méditation en marchant) est un endroit pour écrire, parler et enregistrer pendant que tu marches ou que tu restes immobile. Ce que tu exprimes est conservé sur ton iPhone. Il n’y a ni connexion, ni statistiques d’usage, ni publicité, ni pistage, et Anky n’utilise pas ta localisation.

## 1. Qui nous sommes

Anky est exploitée par **Anky, Inc.**, une société du Delaware. Écris-nous à **[support@anky.app](mailto:support@anky.app)**.

Cette politique couvre l’app Anky pour iOS et le site anky.app. Anky n’est pas un service médical, de santé mentale, de crise, juridique ou financier.

## 2. Ce qui reste sur ton iPhone

Anky conserve ces éléments uniquement sur ton iPhone :

- Tes sessions : écritures (fichiers `.anky`), enregistrements vocaux, vidéos et les détails de chaque session (son début et sa fin, les façons de t’exprimer que tu as choisies et l’étiquette facultative « marcher » ou « rester immobile »)
- Les réflexions que tu as demandées, une fois revenues sur ton iPhone
- Tout brouillon inachevé et l’index utilisé pour lister tes sessions passées
- Tes réglages
- Si tu utilises la barrière Temps d’écran : les apps choisies (sous forme d’identifiants Apple opaques), l’état de la barrière et tes déblocages
- Un identifiant de compte anonyme et aléatoire, conservé dans le trousseau iOS (voir la section 4)

Tes écritures, enregistrements vocaux et vidéos ne sont pas envoyés à Anky. Nous ne pouvons ni les lire, ni les écouter, ni les regarder, et nous n’en avons aucune copie.

## 3. Micro et caméra

Anky utilise le micro uniquement pendant que tu enregistres ta voix, ou le son d’une vidéo, et la caméra uniquement pendant que tu enregistres une vidéo. L’enregistrement commence quand tu appuies sur enregistrer et s’arrête quand tu l’arrêtes. Un enregistrement vocal peut continuer écran verrouillé, pour que le téléphone reste dans ta poche pendant que tu marches ; c’est la seule raison pour laquelle Anky utilise l’audio en arrière-plan.

Les enregistrements sont conservés sur ton iPhone. Ils ne sont jamais envoyés en ligne et jamais transcrits, ni par Anky ni par personne d’autre.

## 4. Ce que reçoit le serveur d’Anky

Il n’y a aucun compte à créer. Au premier lancement, l’app crée sur ton iPhone un identifiant de compte anonyme et aléatoire. Ce n’est ni ton nom, ni ton e-mail, ni ton numéro de téléphone, ni ton identifiant Apple, et il n’est jamais affiché dans l’app. L’app l’utilise pour authentifier les quelques requêtes qu’elle envoie au serveur d’Anky :

- **Vérification des jours offerts et de l’abonnement.** Quand tu ouvres Anky, l’app demande au serveur si tes jours offerts ou ton abonnement sont actifs. Cette requête ne contient aucune écriture, aucun enregistrement ni aucun contenu de session.
- **Registre d’accès gratuit.** Quand tu commences ta première session, le serveur enregistre un hachage SHA-256 à sens unique de ton identifiant anonyme et le moment où tes sept jours offerts ont commencé. Ce registre ne contient rien de ce que tu as écrit, dit ou enregistré. **Il est conservé même après Supprimer toutes les données**, car son seul but est que les sept jours offerts ne commencent qu’une fois par compte et ne puissent pas recommencer. Il ne permet ni de récupérer ni de lire ton contenu.
- **État de l’abonnement.** Si tu t’abonnes, le serveur conserve ton identifiant anonyme avec l’état de ton abonnement (produit, actif ou non, date de renouvellement ou d’expiration), qu’il apprend de RevenueCat (section 6).
- **Réflexions**, uniquement si tu en demandes une (section 5).

Pour que le service fonctionne et pour prévenir les abus, le serveur conserve aussi des compteurs quotidiens de requêtes et, pour les réflexions, un hachage à sens unique du texte réfléchi (pas le texte lui-même), afin qu’une même requête ne soit pas traitée ni facturée deux fois. Notre hébergeur voit ton adresse IP pour acheminer chaque requête ; Anky ne l’utilise que brièvement pour limiter le trafic abusif et ne la conserve pas avec ton identifiant.

## 5. Réflexions par IA (facultatives, réservées aux abonnés)

« Réfléchir avec Anky » est facultatif et réservé aux abonnés. Rien n’est envoyé tant que tu ne le touches pas pour une écriture précise, puis que tu ne confirmes pas.

- **Ce qui est envoyé :** le fichier `.anky` de cette seule écriture, c’est-à-dire son texte et le rythme de ses frappes, avec ton identifiant anonyme et la version de l’app. Les enregistrements vocaux et les vidéos ne sont jamais envoyés.
- **Qui le traite :** le serveur d’Anky transmet l’écriture à un prestataire d’inférence d’IA, qui exécute un grand modèle de langage (actuellement les modèles Claude d’Anthropic, via des services de passerelle d’IA) pour écrire la réflexion. Anky n’utilise que des prestataires configurés pour une conservation zéro des données, sans journalisation du contenu et sans entraînement sur celui-ci ; si aucun prestataire de ce type n’est disponible, aucune réflexion n’est générée.
- **Conservation :** le serveur d’Anky ne conserve ni ton écriture ni la réflexion. Le prestataire du modèle traite le texte uniquement pour générer la réflexion. La réflexion revient sur ton iPhone et y est conservée.

Rien d’autre dans Anky n’utilise l’IA.

## 6. Abonnements et paiement

Anky offre sept jours gratuits de son expérience principale, à partir de ta première session. Aucune information de paiement n’est demandée et rien n’est facturé à leur fin.

L’abonnement est un abonnement mensuel à renouvellement automatique, vendu par Apple via l’App Store. Apple gère le paiement ; Anky ne reçoit jamais ta carte ni tes données de facturation. Anky utilise **RevenueCat** pour gérer les abonnements : RevenueCat reçoit ton identifiant de compte anonyme et tes historiques d’achats et d’abonnements App Store afin d’indiquer à l’app si tu es abonné. Consulte la politique de confidentialité de RevenueCat sur [revenuecat.com/privacy](https://www.revenuecat.com/privacy). Annule ou gère ton abonnement dans les réglages d’abonnement de ton compte Apple.

Si tes jours offerts se terminent et que tu ne t’abonnes pas, tout ce que tu as déjà créé reste sur ton iPhone, lisible et exportable.

## 7. Ce qu’Anky ne fait pas

- Elle n’envoie ni ne transcrit ton écriture, ta voix ou tes vidéos. Le seul contenu qui quitte ton iPhone est une écriture que tu choisis d’envoyer pour une réflexion.
- Elle n’utilise pas ta localisation.
- Elle n’inclut aucun SDK de statistiques d’usage, de rapports de plantage, de publicité ou de pistage, et ne te suit pas d’une app ou d’un site à l’autre.
- Elle ne vend ni ne partage tes données, et ne les utilise pas pour entraîner des modèles d’IA.

## 8. Services Apple que tu peux choisir d’utiliser

- **Sauvegarde iCloud :** si tu l’actives, Anky chiffre tes écritures et tes réflexions avec AES-GCM et enregistre le fichier chiffré dans ton propre iCloud Drive. Les enregistrements vocaux et les vidéos n’y sont pas inclus. Ce qui est nécessaire pour déchiffrer la sauvegarde est enregistré dans ton trousseau iCloud pour que tu puisses la restaurer sur un nouvel iPhone. Apple gère iCloud ; Anky ne voit jamais la sauvegarde.
- **Temps d’écran :** si tu actives la barrière, les frameworks Temps d’écran d’Apple gèrent l’autorisation et le choix des apps. Ta liste d’apps reste sur l’appareil.
- **Notifications :** les rappels et les notifications de la barrière sont programmés localement par iOS.
- **Face ID :** utilisé uniquement pour confirmer que c’est bien toi avant d’activer la sauvegarde iCloud. Apple effectue la vérification ; Anky apprend seulement oui ou non.

Les sauvegardes de ton iPhone lui-même, si tu les utilises, sont gérées par Apple selon ses propres conditions.

## 9. Exporter

**Réglages → Exporter mes souvenirs** crée un seul fichier .zip avec les détails de chaque session, les fichiers audio et vidéo d’origine, tes écritures en `.anky` et en texte brut, et tes réflexions en Markdown. L’export fonctionne avec ou sans abonnement. Ce que tu fais du fichier ensuite dépend de toi.

## 10. Supprimer tes données

Supprime une session ou une écriture depuis son menu. **Réglages → Supprimer toutes les données** efface de ton iPhone chaque session, écriture, enregistrement vocal, vidéo, réflexion et réglage, ainsi que l’identifiant anonyme et ta sauvegarde Anky dans iCloud. Supprimer l’app efface aussi ses données locales.

Supprimer toutes les données n’annule pas un abonnement ; annule-le auprès d’Apple. Le registre anonyme d’accès gratuit décrit à la section 4 est conservé pour que les jours offerts ne puissent pas recommencer. L’état d’abonnement sur le serveur d’Anky et la fiche d’abonné chez RevenueCat ne sont liés qu’à l’identifiant anonyme ; une fois celui-ci effacé de ton iPhone, ces données ne peuvent plus être reliées à toi ni à rien de ce que tu as créé. Pour toute autre demande de suppression, écris à **[support@anky.app](mailto:support@anky.app)**.

## 11. Assistance

Les Réglages peuvent ouvrir ton app de messagerie ou un lien de discussion. Rien n’est envoyé tant que tu ne l’envoies pas, et nous recevons alors ce que tu as choisi d’écrire.

## 12. Enfants, modifications et contact

Anky n’est pas destinée aux enfants de moins de 13 ans. Si cette politique change, nous la mettrons à jour ici et réviserons la date ci-dessus.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
