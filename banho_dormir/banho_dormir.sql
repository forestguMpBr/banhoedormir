-- Execute este SQL no seu banco de dados antes de iniciar o recurso
CREATE TABLE IF NOT EXISTS `banho_dormir_locations` (
    `id`   INT          NOT NULL DEFAULT 1,
    `data` LONGTEXT     NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `banho_dormir_needs` (
  `citizenid` varchar(50) NOT NULL,
  `dirt` tinyint(4) NOT NULL DEFAULT 0,
  `sleep` tinyint(4) NOT NULL DEFAULT 0,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;