<?php
/**
 * Created by PhpStorm.
 * User: ami
 * Date: 10/29/15
 * Time: 12:30 PM
 */

namespace AppBundle\Model;


use AppBundle\Tic\Game;
use Symfony\Component\HttpFoundation\Session\Session;

class GameModel
{
    /** @var  Session */
    private $session;

    /** @var  Game */
    private $game;

    /**
     * GameModel constructor.
     * @param Session $session
     */
    public function __construct(Session $session)
    {
        $this->session = $session;
        $this->loadGame();
        $this->storeGame();
    }

    /**
     * @return Game
     */
    public function getGame()
    {
        return $this->game;
    }

    /**
     * @param Game $game
     */
    public function setGame($game)
    {
        $this->game = $game;
        $this->storeGame();
    }

    private function loadGame()
    {
        $json = $this->session->get('game', $this->emptyGameJson());
        $game = new Game();
        $game->unserialize($json);
        $this->game = $game;
        return $this->game;
    }

    private function storeGame()
    {
        $this->session->set('game', $this->game->serialize());
    }

    private function emptyGameJson()
    {
        $game = new Game();
        $game->start();
        return $game->serialize();
    }

    public function startGame()
    {
        $this->game->start();
        $this->session->set('scoreRaised', 0);
        $this->storeGame();
    }

    /**
     * Change player : pc or human , default is pc.
     * @param $mode
     */
    public function changePlayerMode($mode)
    {
        $this->session->set('playerMode', $mode);
    }

    public function getPlayerMode()
    {
        return $this->session->get('playerMode', 1);
    }

    public function raiseScore($shape)
    {
        $oldScore = $this->session->get('score', $this->getEmptyScore());
        $oldScore[$this->getPlayerMode() === '1'?'pc':'human'][$shape]++;
        $this->session->set('score', $oldScore);
        $this->session->set('scoreRaised', 1);
    }

    /**
     * Check if score was raised to prevent from score to raise each page reload
     */
    public function didScoreRaise()
    {
        return $this->session->get('scoreRaised',0);
    }

    /**
     * Get the score array depending on player mode (human vs pc or 2 players)
     */
    public function getScore()
    {
        $score = $this->session->get('score', $this->getEmptyScore());
        return $score[$this->getPlayerMode() === '1'?'pc':'human'];
    }

    /**
     * Get a clean score array in case there is none saved in session
     */
    public function getEmptyScore()
    {
        return array('pc'=> array('x'=>0,'o'=>0),'human'=> array('x'=>0,'o'=>0));
    }

}