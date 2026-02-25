set_credentials = function(exchange="coinbase",wallet="tradery",client=NULL) {
	exchange=tolower(exchange); 
	if (is.null(client)) { wallet = tolower(wallet) }
	credentials = c(); key = NULL; secret= NULL; passphrase = NULL;
	if (exchange == "coinbase") {
		web = 'https://pro.coinbase.com'
		if (!is.null(client)) { 
			if (client == "richport") { 
				if (wallet == "hera_6h_btc_64_33") { 
					key="534d8134a7739a9a00dff4736ba9e6e2"
					passphrase="qixkagofj3j"
					secret="kATiKWfwfMWPAz8gf/zNgIGUW5rjnINAAh+h+givJ2q9nqVYstfoEiLUOtG7GjeI3fRXw3ZKzMVeBXCMpudWEQ==" 
				}
				else if (wallet == "zeus_6h_btc_50_30_sl") {
                                        key="0c3457ffcd511fe6abcaa9799f48df3b"
                                        passphrase="qdt0j6vs8i"
                                        secret="QHhlkrSWJMN2j3djROcGCbtHu7eXfweUOlepDOK125khS15ZqQa2SIPM/LGdyZ0LcZ8s+gGrdSwY3ijXIal08Q=="
                                }
                                else if (wallet == "zeus_6h_btc_45_25") {
                                        key="a5df38c58d38bebaa3de5ad20a9d949a"
                                        passphrase="4xa5cy07l1q"
                                        secret="Y3BZbOVaIslwEveLvqzCGqnqchsyGpaR3n+yBVcz4U+Qz4U7I0uoqLCj1vrjpLVkPwkItdUmVAUYMvFi+UFpEQ=="
                                }
                                else if (wallet == "zeus_6h_btc_70_30_sl") {
                                        key="3874924e7e2609bc82ebb792b8eaa414"
                                        secret="SRHsX041ti75d3VfUc2+fU9H3X/0+nWAsLlA4jXC5kPHpSQm/lnskdrj/r8MIZc2EjJ8nGhwdmJPCRwdPlDfTQ=="
                                        passphrase="nbh3md397a"
                                }
				else if (wallet == "hera_6h_eth_56_27") { 
					key="ff1d2c45ec763cc551671795ffd1da0c"
					passphrase="7pjxy5l1rwl"
					secret="qT6rU9mX8raUfxLZ8q7EHdVxE85GcWQhMbsrpbygGirNCfpbMUCwinzUU+ir3ovQeclYknpaTQnvYwcYYAoouQ=="
				}
				else if (wallet == "hera_6h_eth_50_30") {
					key = "91d2f51594a5c6a4c444e44eb93ca2b7"
					passphrase = "xj08r2tf23"
					secret = "nv8ZTnqlUkL94J08UJBAPjid71Dcbq5i7Tk+tmltHNHDq+5vX/3xbnsHJ8+BNWrw+3fhHsYRacYIUXehTQfvEg=="
				}
                                else if (wallet == "hera_1d_matic_55_28") {
                                        key = "8cfe29bb0de33ac85facf334da810197"
                                        passphrase = "1e8cvg3ggvo"
                                        secret = "QpWVQ9proV3ccaXxxn9x7OkbN10gaKjURDJnN0EeWa/JQ/XvBocvZbuI1NvtsrEX78bYFGEROpDc3OdXO1EN1w=="
                                }
				else if (wallet == "hera_1d_op_55_28") {
                                        key = "bf95690b720097f5aa79f8a7cbc35f45"
                                        passphrase = "kk78pnoox2g"
                                        secret = "tagSY2tWgi209qyfJHOqekzwwOUg+m2jqEIvbCbm030ZueTWZjg2qPuWzl+8qfVMq6N9Na0xVdps7U+khr5uMA=="
                                }
                        	else if (wallet == "hera_6h_ltc_56_27") { 
					key="cfa108622690f2f33b3172d6e424fa7d"
					passphrase="3xkcajqz41"
					secret="xz+KU40K+MK7AhRNmLwYhJNj5vTeioFRlEeeyG/hxAgUi5D8yPHo4ydJPGPrQZZLHNXWN7IyNEE2Je0m+lMQSw=="
				}
                        	else if (wallet == "hera_1h_ltc_70_30") { 
					key="b4e18616428d35ca5803875573dec5d6"
					passphrase="x95e2q8llto"
					secret="w2AWFS2pt5Omet5izAIbFurJjQRwZ9CPvMak0byIjdIdikOQy8j/2Q1CH46ZU0f2DzDji0vzt/Wy0bLQkYofdw=="
				}
                                else if (wallet == "hera_1d_eth_70_30") {
	                                key="69d7b714fbdf1fe5eacac8f3b26ce61d"
                                        passphrase="j798v51m0ej"
	                                secret="2u95rEc04fgBK+q2iJZ67zmP7XcItex+DuObtoxLteN/GI+Nz1PYqErTCgD/9mRvL6NWehgBcryiw191QyJ8Xg=="
				}
                                else if (wallet == "hera_1d_btc_70_30") {
	                                key="cda99c04c1ae1c737a28e34a5537f526"
                                        passphrase="p4mh42erifg"
	                                secret="y4l6LMf2hU0TIb3RDKFmBlLYWa2MZDi1Y6jxoONfA91zNK6YF1ZkaBnCgs17KmVUkX76kDuu07UwH/pUz8uPkA=="
	                        }
                                else if (wallet == "hera_1h_eth_70_30") {
	                                key="4a8262d7efe2a92a2e7f7ec565d2c606"
                                        passphrase="w4u3ydzyf"
	                                secret="Xi2RbTIO4SW7vlkL5TOZ86iRufl7+V3HjPGHGjgrowysmuvq5bY7uZndEi225r9U84aQ48RIOCErx9uLY28pHA=="
	                        }
                                else if (wallet == "hera_1h_btc_70_30") {
	                                key="7f822f0014a3cbee11be7c3516a386a3"
                                        passphrase="7pwmt8p7uyo"
	                                secret="0UpWEWGsTOb24Q0JSQbOn7uSDZksU/Y9mpk080Yy5F85lhAzuYuhP8wasdAyEmIzDda4qrD5MqADm9BY9wfCRA=="
	                        }
				else if (wallet == "hera_6h_link_54_29_sl") { 
					secret = "D9bNDlBDzNA/TDMbcehK29TXroK/qkfmYxCHG2EslrBi1UfxJZ1E+o6cfTAEbaGiiqQoGC4NlZXsKQjvIDkT5A=="
					passphrase = "qxuoewislhe"
					key = "8f47164ce5b3b00a294e60a716094cc7"
					}
                                else if (wallet == "hera_6h_link_55_20") {
	                                key = "50462091c72713474979ce9edf76bfab"
                                        passphrase = "1c68qow3eqy"
	                                secret = "+nGmn2Lne1NFalN+rjCFKfZD5qIoOK4Tiwtr5SDKzpsUaf6Z/LU0skFhT5aDXIb/pvEvGMVaX4vhMeqD3n7/rQ=="
	                        }				
			}
			else if (client=="alphasigma") {
					if (wallet == "hera_1d_btc_63_27") {
						key = "67b4db33fb9178e632d6e29405898080"
						passphrase ="tb89ys19km"
						secret = "h8WEOGhVBlngkzLO+rkqzRfxr5i4SPfPmD7lsQ0ZNM+OxVyGNcrYS0zJSOMeUZoEybdWaSdpdCJXMhKnt8ey7Q=="
					}
					else if (wallet == "hera_1d_eth_50_30") {
					      key = "336e7cc16754099ca9591cd0b5e75c09"	
			                      passphrase = "cfsdkej1ce"
                                              secret = "KNRkvb9/wkcUVw1Yy5/nxljnDQXmkCQDEFMiFfBoaXXPT/kTmCcW1wkieN0KWMOmT+Kzvh2ir6FyM1QYQE7N3g=="
                                        }
                                        else if (wallet == "hera_1d_eth_63_27") {
                                              key = "1b518ce7f2f22446f0f533cb02eb6af4"
                                              passphrase = "vw403ffvods"
                                              secret = "o9m2n1cyI10feIIrg/2/eoAlDmVzmVGc1Ey7TAx2oT5N9FYgWAgosbjwyplbF6jeB0tADZzPHCQe7TAUmq2mvA=="
                                        }
                                        else if (wallet == "hera_1d_btc_50_30") {
                                              key = "44d2e3627c48d15c98cd5492f1084692"
                                              passphrase = "n4runh42ci"
                                              secret = "VYXoJQ6ucFjlM0c2XRZwcUjyDLc3JegzrYwZctlqfUoU9xdTK7Nwp9Os5kOrQkiba1uCY6wRbQcGphrtcg88rQ=="
                                        }
					else if (wallet == "hera_1d_btc_60_40") { 
						key = "eb1a5a325f0aee25b733baf236d6b63c"
						secret = "HDB3WXRplmYYt9iE+V0NBrAbWv3/LYRn5QLIPeyA6OCPbd4TvK6/DNVj7yf2OyqGAMAvzUiIrwyCNz119GEIWA=="
						passphrase = "z52tc0ofx3"
					}
					else if (wallet == "hera_1d_eth_60_40") {
						key = "a2f688fe87e67170ff3e54cab58d6403"
						secret = "XKb61rMh8NwiyrGK4qFi9Oc9LU6HCxSDpQfnUIJD1KZEzALBnGfCdYVoygc91K+ksjNHNtaF3l3trLKyeEDlqQ=="
						passphrase = "w8jz3ml06o"
					}		
			}  
			else if (client=="tradery") {
				if (wallet == "hera_6h_aave_70_30") { 
					key = "997edf7256408db5579af110e0e16c31"
					secret= "GzM9kbrUq/51hC+ZyeRPDGCzhQbIIxl4Jh4oY8JsMRtvkBodpjhsAVqHpwuHawRlBuJ0IPKTjQjRNrNWVldIcw=="
					passphrase="3gyi1ukcipi"
				}
				else if (wallet=="hera_6h_link_70_30") {
					key = "3f84712814a05dd4d2f085aa62cbab0e"
					secret="BmsfBJPgwiQg5J2LUqBsikdS6JS0/lh931qu2y91hRUMlITzCpBiSSjizoJNad1O7mf4D5r/RJ3YJftJnwaLtw=="
					passphrase="pjd2u61ybb"
				}
				else if (wallet=="hera_1h_crv_70_30") { 
					key = "c1ef641488f158e1a71318b02240f798"
					secret="CN5MkjMghQJghrCWHu/OpBAhnhSLEUViVJbmmq+djeoQgDeyGCKCf5yjPQ808gV4V9oITXGYugyYAxNuke9Bjw=="
					passphrase="gikm051f5cs"
				}
				else if (wallet == "hera_6h_link_80_20") { 
					key = NULL
					secret = NULL
					passphrase = NULL
				}
                                else if (wallet=="hera_1h_eth_70_30") { 
					key = "803eb9d4313a2e3e5d54d7ee6c442bfb"
					secret="LDHoWCrFgBiop6S9nNMZU02jH92tA/XvBh+IZtp6qhaLRwILG0cGXDlZyypbmzJ6/JeUwX7OsTIp4FXVQOmoWw=="
					passphrase="a0nzzk0vzm7" 
				}
				else if (wallet == "hera_1d_btc_70_30") { 
					key = "267e6bd8f3beee1201bbec4442197d95"
					secret= "1dWPhaSfEgpb/2tDpIxTWsQs+ggU+FOV/z5FskHxu0qu7aUOFzaPYEipA4t+3xT0U20CTUrxY4JEgLoaQaHAIQ=="
					passphrase = "n81zvacj9h"
				}
				else if (wallet == "hera_1d_eth_70_30") {
				        key = "87877039fb6acd4dc79cf99181a91919"
					secret= "n8z5S+2bSveuBDnMX3dCbTM4H5AwomPe8CrARlGgA3/SBWFS9wI4UOTeCautMyqhK9W1YQ27ct0mpuly+gkh5g=="
					passphrase ="15o80cqsubh"
				}
                                else if (wallet == "hera_6h_ada_70_30") {
	                                key = "231c2cf9f821169cd9afe2aa250533c4"
                                        secret= "PFYlRpNyCw2VXVCTaCOgSol6y+eBKw8+iNdiJc5GYyBAKOICW5P9EUJ6dBgUVrGfxCLVjLRPQgsw3rQZ2ItOBA=="
	                                passphrase ="4tf5x8lkcx4"
	                        }
				else if (wallet == "hera_6h_uni_70_30") { 
					key = "f5a3f1619f0598790188cf9f82735460"
					secret = "rOI+K1Zie8I5y3pcyVAGoj7vfmmq/W90EezM0v/g/YsgERXozphg/E/othdIJh+7HA+iqf+G2oIOSzGPmrFZww=="
					passphrase = "p3tc5g8iz5"
				}
				else if (wallet=="hera_6h_sol_70_30") {
					key = "13e436d3bc93b1243cc65e838e169c1c"
					secret = "Uw1x+EdQgMMz1vz0LPo5tl3jGj11zge290fJ5cDUdbNgJunNPli60nNGiskWtdPWlPQiLcAls39gHYOrmKY8yg=="
					passphrase = "umrjtropn1b"
				}
				else if (wallet == "hera_6h_ltc_70_30") { 
					key="c2a9dd1a60aa885752780165e82fd157"
					passphrase="fk8dcns7f1b"
					secret="EYJpPfmfxOQhZpv3Ah4UE4fzOI25amdncNHJqF2jxIh5F1f8SsFF1tkl/3X1fMeMAKbhd2bnedqXUEWsm5SXUg=="
				}
				else if (wallet == "hera_6h_link_70_30_sl") { 
					key="ea29a8f704b2b40c87a1925b2c5e1319"
					passphrase="24277qtzlb7"
					secret="rVV1UFCELhi+VC4OBbTY7WAYsC1TnB3XuzTJa2/ekW7Vanv63bzmPgi25LrS3FJGrpKQKuLf+3zsubEjKcp06w=="	
				}
				else if (wallet == "hera_6h_btc_70_30") {
					key = "bca1ba2e3ee4c0504a5c4e84a5ac1484"
					passphrase = "nk2yfjrzbsi"
					secret = "q26EfxidN2GmnLchMFDSSCgligo+y/Lda4oOqqCTUPxbOMBW9b3I3+79HcfSDbIL3sujDdEzhj7KcyxM5pkxJA=="
				}
				else if (wallet == "hera_6h_eth_70_30") {
					key = "31fe00cf2ceeb32a887460c7b6299341"
					passphrase = "1hl5chd59mi"
					secret = "ygxGAuDStRsNYV6YKv2bjYuuFVTaSRyvCJh4IYcq9APtrjCH3PDc/tUGPbo3fwKfkHNoyk3SpnLPO1pbS0oo5Q=="
				}
				else if (wallet == "hera_6h_orn_70_30") { 
					key = "de464f93b5f073ab0f2fca7ff57ae326"
					passphrase = "7o9d1mdbev8"
					secret = "4FMCOmD8pkNx2XYvAC5J0a4C/0A8Z3Z1jo73F1M3R7ctdlXg37qO6/V7fCkCJdMtWoeMd9tyuAZY3FJZX370mw=="
				}
				else if (wallet == "hera_6h_matic_52_28_sl") { 
					key = "e8004d821a3702ebebc068eb778b3352"
					passphrase = "6p5t9pughc7"
					secret = "UI1nndoMlK3XZow+AOgMe3hmcfC0Ft+PDShpxuQ2xNFWKWdzi+ComKqeBGRLu2Jol2O/XiIy25G2Sdv8RhALJA=="
				}
				else if (wallet == "hera_15m_matic_52_28_sl") {
					key = "66f9bb4251fcbcf7688d573a24761794"
					secret = "HiYzM3aEoFk/UKpkPLiIlG0bYzTYkVsRa29vvCHPjcl/qa49MqI1KUAs86nJxd2c2SxJNMQtlOvAmcq9szo+wA=="
					passphrase = "jfaqdhyqop"
				}
				else if (wallet == "hera_6h_op_52_28") {
					key = "d872b28380dd34a3c4dfabd9a3f5fa16"
					secret = "6cV3gqRCpyt7DQX76BSt7HPij2EmLzLowgEL1biCFEHR7GR+OM/pNgIecepzjn8XCy0jkCXwCgJAcsVYEkGkrA=="
					passphrase = "q2f9p8v37ab"
				}
				else if (wallet == "hera_6h_atom_52_28") {
				        key = "1f7ea05baec99c9e8a21e9d1ffc20d02"
				        secret = "+38ZO8LhMpNf2rpmqNFfudZN5i5GO/X9dL7aYOsqo8Yb1/Qz3yGlAr4rUYTPCDexUjLCSSi0mxOQWFnNe3UcvA=="
				        passphrase = "911mj05wecl"
				}
				else if (wallet == "hera_6h_ldo_56_27_sl") { 
					key = "267e9cb2514674d1debb04a1f79333d5"
					secret = "MevveiHPowiJ4IjsCILddpghY2rknCEZxkbWwg3SpCmHWHHXkuQ6leG04vRcG+jLBZoOP1pMBC3ETC6gRM2g3g=="
					passphrase = "6ilntmfohfm"
				}
			}	
		}
		else if (wallet == "aslan_zeus_6h_matic") { 
			key="5b3cd165f52261ecc591aa9bd7a6fba4"
			passphrase="tuz9n7sgnxe"
			secret="1s9hJePmQsp8HJcSANHoeJeWV4gnz6uDRG+Jgvym0PA2jtkC4z/LUt73HUJZ/NmsTpt+qMmzbr8pqeiiR/j0Ew=="
		}
	        else if (wallet == "aslan_morpheus_1h_dot") { 
			key="eabc60ad6bc3df6758e27e24f9bdaae9"
			passphrase="lb7cs1t33bp"
			secret="IaNQgE9EU1AcC44Ze04Y5dBvedD/LekGA9iDeWG0G99/wG9VuGsQNcEEUZP1OqU+MFmjpNDw3Khr4kY8TnN46Q=="
		}
		else if (wallet == "aslan_ares_1d_btc") { 
			key="fe26d6abe0de8371d2cdc4c3f25a9257"
			passphrase="iv93saovli"
			secret="5mXbn2iVzv8Jg9rWVWT2yLwqdZhe5jqtcBTDOJhptangDMq+p+jM7O+o8xOH+mvcn4CsL1fjNwEJzmV0udwcjg=="
		}
		else if (wallet == "tradery_zeus_btc_6h_trading") { 
			key="bca1ba2e3ee4c0504a5c4e84a5ac1484"
			passphrase="nk2yfjrzbsi"
			secret="q26EfxidN2GmnLchMFDSSCgligo+y/Lda4oOqqCTUPxbOMBW9b3I3+79HcfSDbIL3sujDdEzhj7KcyxM5pkxJA=="
		}
		else if (wallet == "tradery_ares_eth_1d_trading") {
			key="31fe00cf2ceeb32a887460c7b6299341"
			passphrase="1hl5chd59mi"
			secret="ygxGAuDStRsNYV6YKv2bjYuuFVTaSRyvCJh4IYcq9APtrjCH3PDc/tUGPbo3fwKfkHNoyk3SpnLPO1pbS0oo5Q=="
		}
                else if (wallet == "tradery_morpheus_btc_1d_trading") {
		        key="38cf9b1152cb9ddd022f436afd1967df"
			passphrase="op5tcv3295p"
			secret="KRuolnIi2j2+jElhTUu0T58s1HYVzysMjs/37eGTY4ZvzbLlticFNMp6TVj25A7VGYrb6r35KhnAvQvGf/qjrQ=="
		}
	}
	if (!is.null(key) && !is.null(secret)&& !is.null(passphrase)) { credentials = list(key=key,passphrase=passphrase,exchange=exchange,secret=secret,wallet=wallet,web=web) }
 	if (!is.null(credentials)) { class(credentials) <- "credentials"; assign("credentials", credentials, envir = .GlobalEnv) }
	return(credentials)
}

